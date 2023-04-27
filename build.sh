#!/usr/bin/env bash

set -euo pipefail

readonly TARGET_DIRECTORY="/workdir/artifacts"                                          # 存放生成的 Debian 包的目录
readonly DATETIME="${DATETIME:-$(date +%Y%m%d)}"                                        # 当前日期时间，格式为 YYYYMMDD
readonly LINUX_DISTRO="$(lsb_release -cs)"                                              # 本地 Linux 发行版的代号
readonly DEBIAN_INCREMENT="${DEBIAN_INCREMENT:-3}"                                      # Debian 的版本号增量
readonly ARCHITECTURE="$(dpkg --print-architecture)"                                    # 本地机器的架构
readonly DEB_SUFFIX="${DEBIAN_INCREMENT}${LINUX_DISTRO}~${DATETIME}_${ARCHITECTURE}.deb" # Debian 包文件名后缀

readonly RED='\033[31m'    # 红色控制台输出
readonly GREEN='\033[32m'  # 绿色控制台输出
readonly YELLOW='\033[33m' # 黄色控制台输出
readonly NC='\033[0m'      # 恢复默认控制台输出颜色

sudo mkdir -p "${TARGET_DIRECTORY}/${LINUX_DISTRO}"

cat <<EOF >~/.ros/rosdep.yaml
depthai:
  ubuntu: [ros-${ROS_DISTRO}-depthai]
  debian: [ros-${ROS_DISTRO}-depthai]
depthai_ros_msgs:
  ubuntu: [ros-${ROS_DISTRO}-depthai-ros-msgs]
  debian: [ros-${ROS_DISTRO}-depthai-ros-msgs]
depthai_bridge:
  ubuntu: [ros-${ROS_DISTRO}-depthai-bridge]
  debian: [ros-${ROS_DISTRO}-depthai-bridge]
foxglove_msgs:
  ubuntu: [ros-${ROS_DISTRO}-foxglove-msgs]
  debian: [ros-${ROS_DISTRO}-foxglove-msgs]
depthai_examples:
  ubuntu: [ros-${ROS_DISTRO}-depthai-examples]
  debian: [ros-${ROS_DISTRO}-depthai-examples]
depthai_descriptions:
  ubuntu: [ros-${ROS_DISTRO}-depthai-descriptions]
  debian: [ros-${ROS_DISTRO}-depthai-descriptions]
depthai_filters:
  ubuntu: [ros-${ROS_DISTRO}-depthai-filters]
  debian: [ros-${ROS_DISTRO}-depthai-filters]
depthai_ros_driver:
  ubuntu: [ros-${ROS_DISTRO}-depthai-ros-driver]
  debian: [ros-${ROS_DISTRO}-depthai-ros-driver]
depthai_ros:
  ubuntu: [ros-${ROS_DISTRO}-depthai-ros]
  debian: [ros-${ROS_DISTRO}-depthai-ros]
EOF

#echo "yaml file:///${HOME}/.ros/rosdep.yaml" > /etc/ros/rosdep/sources.list.d/50-my-default.list

rosdep update --include-eol-distros --rosdistro "${ROS_DISTRO}"

# 打印信息
info() {
    local message="$1"
    printf "${GREEN}[INFO] %s${NC}\n" "${message}"
}

# 打印警告
warn() {
    local message="$1"
    printf "${YELLOW}[WARN] %s${NC}\n" "${message}" >&2
}

# 打印调试信息
debug() {
    local message="$1"
    if [[ "${DEBUG:-}" ]]; then
        printf "${GREEN}[DEBUG] %s${NC}\n" "${message}" >&2
    fi
}

# 检查是否支持当前 Linux 发行版
distro_supported() {
    [[ "${ARCHITECTURE}" == "amd64" ]] && [[ "${LINUX_DISTRO}" != "buster" ]]
}

# 拉取 Git 仓库
clone_repo() {
    local repo_url="$1"
    local branch="$2"
    local repo_name="$(basename "${repo_url}" .git)"

    if [[ -d "${repo_name}" ]]; then
        warn "Directory ${repo_name} already exists. Skipping clone."
        return 0
    fi

    git clone --recursive --depth 1 -b "${branch}" "${repo_url}" "${repo_name}"
}

# 应用补丁
apply_patch() {
    local patch_file="$1"

    if ! [[ -f "${patch_file}" ]]; then
        warn "Patch file ${patch_file} not found. Skipping patch."
        return 0
    fi

    info "Applying patch file ${patch_file}..."
    git apply --ignore-space-change "${patch_file}" || {
        warn "Failed to apply patch file ${patch_file}"
        return 1
    }
}

# 删除 VCS 文件
remove_vcs_files() {
    info "Removing VCS files..."
    find . -type d \( -name '.git' -o -name '.svn' \) -print0 |
        xargs -0 rm -rf --
}

# 创建原始 tar 包
create_orig_tarball() {
    local dir_name="$1"
    local ros_pkg_name="$2"
    local orig_tar="${ros_pkg_name}.orig.tar.xz"

    if ! distro_supported; then
        return 0
    fi

    info "Creating ${orig_tar} ..."
    (cd .. && tar --exclude-vcs -cJf "${orig_tar}" "${dir_name}") || {
        warn "Failed to create ${orig_tar}"
        return 1
    }
}

# 生成 Debian 文件
generate_debian_files() {
    local version="$1"

    info "Generating Debian files..."

    if ! bloom-generate rosdebian -i "${DEBIAN_INCREMENT}"; then
        warn "Failed to generate Debian files"
        return 1
    fi

    local origin_version="${version}-${DEBIAN_INCREMENT}${LINUX_DISTRO}"
    local version_date="${origin_version}~${DATETIME}"

    sed -i -e "s/(${origin_version})/(${version_date})/g" debian/changelog || {
        warn "Failed to update debian/changelog"
        return 1
    }
}

# 安装 ROS 包依赖项
install_ros_pkg_deps() {
    local pkg_dir="$1"
    info "Installing dependencies for ${pkg_dir}..."

    if ! rosdep install --from-paths "${pkg_dir}" --ignore-src -r -y; then
        warn "Failed to install dependencies for ${pkg_dir}"
        # return 1
    fi
}

# 打包源代码
package_source() {
    local pkg_name="$1"
    if ! distro_supported; then
        return 0
    fi
    info "Building source package for ${pkg_name}..."
    dpkg-buildpackage -S -j"$(nproc)" || {
        warn "Failed to build source package for ${pkg_name}"
        return 1
    }
}

# 获取 ROS 包的版本号
get_package_version() {
    sed -n '/<version>/p' package.xml | sed -E 's|.*>([0-9.].*)<.*|\1|g'
}


build_package() {
    local package_type="$1"          # 包类型：core/foxglove/ros
    local dir_name="$2"              # 目录名称
    local pkg_name="${3:-$dir_name}" # 包名称，默认为目录名称
    local version                    # 包版本号
    local ros_pkg_name               # ROS包名称
    local deb_name                   # Debian包名称
    local base_dir="/tmp"            # 基础目录
    local repo_url                   # 仓库URL
    local branch                     # 分支名称

    case "${package_type}" in
    core)
        repo_url="https://github.com/luxonis/depthai-core.git" # core包的GitHub仓库URL
        branch="ros-release"                                   # core包对应的分支
        ;;

    foxglove)
        repo_url="https://github.com/foxglove/schemas.git" # foxglove包的GitHub仓库URL
        branch="main"                                      # foxglove包对应的分支名称
        base_dir="${base_dir}/schemas"                     # foxglove包的基础目录
        ;;

    *)
        repo_url="https://github.com/luxonis/depthai-ros.git" # ros包的GitHub仓库URL
        branch="humble"                                       # ros包对应的分支名称
        base_dir="${base_dir}/depthai-ros"                    # ros包的基础目录
        case "${ROS_DISTRO}" in
        kinetic | melodic | noetic)
            branch="noetic" # 如果ROS发行版是kinetic、melodic或noetic，则使用noetic分支
            ;;
        foxy)
            branch="foxy" # 如果ROS发行版是foxy，则使用foxy分支
            ;;
        esac

        ;;
    esac

    cd "/tmp"

    clone_repo "${repo_url}" "${branch}" # 克隆代码仓库

    cd "${base_dir}/${dir_name}"

    if [[ "${package_type}" == "core" ]] && [[ "${ROS_DISTRO}" == "kinetic" ]]; then
        apply_patch /workdir/xenial_package.diff # 如果是core包且ROS发行版是kinetic，则应用补丁
    fi

    remove_vcs_files # 移除VCS文件

    install_ros_pkg_deps "${base_dir}/${dir_name}" # 安装ROS包依赖

    # 检查是否存在需要修改的文件
    local file_count
    file_count=$(find "." -name "*.cfg" | wc -l)
    if [ "$file_count" -eq 0 ]; then
      warn "目录 ${base_dir}/${dir_name} 中没有任何 .cfg 文件"
    else
      # 设置文件为可执行
      find "." -name "*.cfg" -type f -print0 | xargs -0 chmod +x --
      # 在文件首行添加 Python 解释器路径
      find "." -name "*.cfg" -type f -print0 | xargs -0 sed -i "1i#!/usr/bin/env python" --
    fi

    version="$(get_package_version)" # 获取包版本号

    ros_pkg_name="ros-${ROS_DISTRO}-${pkg_name}_${version}" # ROS包名称

    info "Building Debian package ${ros_pkg_name}..." # 提示正在构建Debian包

    create_orig_tarball "${dir_name}" "${ros_pkg_name}" # 创建原始tarball

    generate_debian_files "${version}" # 生成Debian文件

    if [[ "${package_type}" == "core" ]]; then
        cp "/workdir/postinst_depthai_core" "/tmp/depthai-core/debian/postinst" # 如果是core包，则复制后安装脚本
    fi

    package_source "${pkg_name}" # 打包源代码

    if [[ "${package_type}" == "core" ]] && { [[ "${ROS_DISTRO}" == "kinetic" ]] || [[ "${ROS_DISTRO}" == "melodic" ]] || [[ "${LINUX_DISTRO}" == "buster" ]]; }; then
        info "Building ${ros_pkg_name} binary package with BUILD_TESTING_ARG and OpenCV_DIR..."                                                               # 提示正在使用BUILD_TESTING_ARG和OpenCV_DIR构建二进制包
        env DEB_BUILD_OPTIONS=noautodbgsym BUILD_TESTING_ARG="-DOpenCV_DIR=/home/ubuntu/OpenCV4.2/lib/cmake/opencv4" dpkg-buildpackage -b -us -uc -j"$(nproc)" -Zgzip # 使用BUILD_TESTING_ARG和OpenCV_DIR构建二进制包
    else
        info "Building ${ros_pkg_name} binary package..."                    # 提示正在构建二进制包
        env DEB_BUILD_OPTIONS=noautodbgsym dpkg-buildpackage -b -us -uc -j"$(nproc)" -Zgzip # 构建二进制包
    fi

    deb_name="${ros_pkg_name}-${DEB_SUFFIX}"         # Debian包名称
    info "Installing Debian package ${deb_name}..." # 提示正在安装Debian包
    sudo apt install -qq -y "../${deb_name}"        # 安装Debian包

    info "Copying artifacts to ${TARGET_DIRECTORY}/${LINUX_DISTRO}/..."                 # 提示正在将构建结果拷贝到目标目录
    sudo cp -u "${base_dir}/ros-${ROS_DISTRO}"-* "${TARGET_DIRECTORY}/${LINUX_DISTRO}/" # 将构建结果拷贝到目标目录
}

# 构建depthai-ros相关的ROS包
build_depthai_ros_package() {
    build_package ros depthai_ros_msgs depthai-ros-msgs         # 构建depthai_ros_msgs包
    build_package ros depthai_bridge depthai-bridge             # 构建depthai_bridge包
    build_package ros depthai_descriptions depthai-descriptions # 构建depthai_descriptions包
    build_package ros depthai_filters depthai-filters           # 构建depthai_filters包
    build_package ros depthai_examples depthai-examples         # 构建depthai_examples包
    build_package ros depthai_ros_driver depthai-ros-driver     # 构建depthai_ros_driver包
    build_package ros depthai-ros depthai-ros                   # 构建depthai-ros包
}

if [ -z "${PACKAGE}" ]; then
    while getopts "cfra" arg; do
        case $arg in
        c)
            build_package core depthai-core depthai # 构建depthai-core包
            ;;
        f)
            build_package foxglove ros_foxglove_msgs foxglove-msgs # 构建ros_foxglove_msgs包
            ;;
        r | a)
            if [ "$arg" = "a" ]; then
                build_package core depthai-core depthai                # 构建depthai-core包
                build_package foxglove ros_foxglove_msgs foxglove-msgs # 构建ros_foxglove_msgs包
            fi
            build_depthai_ros_package # 构建depthai-ros相关的ROS包
            ;;
        *)
            warn "Invalid argument: $arg" # 非法参数
            exit 1
            ;;
        esac
    done
else
    if [ "${PACKAGE}" = 'depthai' ]; then
        build_package core depthai-core depthai # 构建depthai-core包
    elif [ "${PACKAGE}" = 'foxglove-msgs' ]; then
        build_package foxglove ros_foxglove_msgs foxglove-msgs # 构建ros_foxglove_msgs包
    elif [ "${PACKAGE}" = 'depthai-ros' ]; then
        build_depthai_ros_package # 构建depthai-ros相关的ROS包
    elif [ "${PACKAGE}" = 'all' ]; then
        build_package core depthai-core depthai                # 构建depthai-core包
        build_package foxglove ros_foxglove_msgs foxglove-msgs # 构建ros_foxglove_msgs包
        build_depthai_ros_package                              # 构建depthai-ros相关的ROS包
    fi
fi

shift $((OPTIND - 1))
if [ $# -gt 0 ]; then
    warn "Invalid argument: $1" # 非法参数
    exit 1
fi
