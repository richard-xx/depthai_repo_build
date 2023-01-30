#!/bin/env bash

GREEN='\033[0;32m'
NC='\033[0m'
datetime=${DATETIME:-$(date +%Y%m%d)}
# GREEN=' '
# NC=' '
debian_inc="3"

ROS1_DISTROS="kinetic melodic noetic"
ROS2_DISTROS="foxy galactic humble"

codename=$(lsb_release -c -s)
sudo mkdir -p /workdir/artifacts/"${codename}"/

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
depthai_ros_driver:
  ubuntu: [ros-${ROS_DISTRO}-depthai-ros-driver]
  debian: [ros-${ROS_DISTRO}-depthai-ros-driver]
depthai_ros:
  ubuntu: [ros-${ROS_DISTRO}-depthai-ros]
  debian: [ros-${ROS_DISTRO}-depthai-ros]
EOF

rosdep update --include-eol-distros --rosdistro ${ROS_DISTRO}

depthai_core() {
    dir_name="depthai-core"
    pkg_name="depthai"

    echo -e "${GREEN}Clone ${dir_name} ...${NC}"
    cd /tmp || exit
    git clone --recursive https://github.com/luxonis/depthai-core.git --depth 1 -b ros-release

    cd depthai-core || exit

    if [ "${ROS_DISTRO}" = "kinetic" ]; then
        echo -e "${GREEN}Patch for %s ...${NC}" "${codename}"
        git apply /workdir/xenial_package.diff
    fi

    echo -e "${GREEN}Delete vcs files ...${NC}"
    rm -rf ./.git
    rm -rf ./*/*/.git

    version="$(sed -n '/<version>/p' package.xml | sed -E 's|.*>([0-9.].*)<.*|\1|g')"
    ros_pkg_name=ros-"${ROS_DISTRO}"-"${pkg_name}"_"${version}"

    echo -e "${GREEN}Build ${ros_pkg_name} ...${NC}"

    if [ "$(dpkg --print-architecture)" = "amd64" ] && [ "${codename}" != "buster" ]; then
        orig_tar="${ros_pkg_name}.orig.tar.xz"
        echo -e "${GREEN}Create ${orig_tar} ...${NC}"
        tar --xz -cf ../"${orig_tar}" "../${dir_name}"
    fi

    echo -e "${GREEN}Create debian files ...${NC}"
    bloom-generate rosdebian -i "${debian_inc}"
    sed -i -e "s/(${version}-${debian_inc}${codename})/(${version}-${debian_inc}${codename}~${datetime})/g" debian/changelog
    cp /workdir/postinst_depthai_core debian/postinst

    if [ "$(dpkg --print-architecture)" = "amd64" ] && [ "${codename}" != "buster" ]; then
        echo -e "${GREEN}Build ${pkg_name} source package ...${NC}"
        dpkg-buildpackage -S -j"$(nproc)"
    fi

    echo -e "${GREEN}Build ${ros_pkg_name} binary package ...${NC}"
    if [ "${ROS_DISTRO}" = "kinetic" ] || [ "${ROS_DISTRO}" = "melodic" ] || [ "${codename}" = "buster" ]; then
        env BUILD_TESTING_ARG="-DOpenCV_DIR=/home/ubuntu/OpenCV4.2/lib/cmake/opencv4" dpkg-buildpackage -b -j"$(nproc)" -Zgzip
    else
        dpkg-buildpackage -b -j"$(nproc)" -Zgzip
    fi

    echo -e "${GREEN}Install ${ros_pkg_name} deb ... ${NC}"
    deb_name="${ros_pkg_name}-${debian_inc}${codename}~${datetime}_$(dpkg --print-architecture).deb"
    sudo apt install -qq -y ../${deb_name}

    sudo mkdir -p /workdir/artifacts/"${codename}"/
    sudo cp -u ../ros-"${ROS_DISTRO}"-* /workdir/artifacts/"${codename}"
}

foxglove_msgs() {
    dir_name="ros_foxglove_msgs"
    pkg_name="foxglove-msgs"

    echo -e "${GREEN}Clone ${dir_name} ...${NC}"
    cd /tmp || exit
    git clone --recursive https://github.com/foxglove/schemas.git --depth 1 -b main
    cd schemas/"${dir_name}" || exit

    version="$(sed -n '/<version>/p' package.xml | sed -E 's|.*>([0-9.].*)<.*|\1|g')"
    ros_pkg_name=ros-"${ROS_DISTRO}"-"${pkg_name}"_"${version}"

    echo -e "${GREEN}Build ${ros_pkg_name} ...${NC}"

    if [ "$(dpkg --print-architecture)" = "amd64" ] && [ "${codename}" != "buster" ]; then
        orig_tar="${ros_pkg_name}.orig.tar.xz"
        echo -e "${GREEN}Create ${orig_tar} ...${NC}"
        tar --xz -cf ../"${orig_tar}" "../${dir_name}"
    fi

    echo -e "${GREEN}Create debian files ...${NC}"
    bloom-generate rosdebian -i ${debian_inc}
    sed -i -e "s/(${version}-${debian_inc}${codename})/(${version}-${debian_inc}${codename}~${datetime})/g" debian/changelog

    if [ "$(dpkg --print-architecture)" = "amd64" ] && [ "${codename}" != "buster" ]; then
        echo -e "${GREEN}Build ${pkg_name} source package ...${NC}"
        dpkg-buildpackage -S -j"$(nproc)"
    fi

    echo -e "${GREEN}Build ${ros_pkg_name} binary package ...${NC}"
    dpkg-buildpackage -b -j"$(nproc)" -Zgzip

    echo -e "${GREEN}Install ${ros_pkg_name} deb ... ${NC}"
    deb_name="${ros_pkg_name}-${debian_inc}${codename}~${datetime}_$(dpkg --print-architecture).deb"
    sudo apt install -qq -y ../${deb_name}

    sudo mkdir -p /workdir/artifacts/"${codename}"/
    sudo cp -u ../ros-"${ROS_DISTRO}"-* /workdir/artifacts/"${codename}"
}

build_package() {
    dir_name="$1"
    if [ -z "$2" ]; then
        pkg_name="$1"
    else
        pkg_name="$2"
    fi

    cd /tmp || exit
    if [ ! -f "depthai-ros" ]; then
        [[ ${ROS1_DISTROS} =~ (^|[[:space:]])${ROS_DISTRO}($|[[:space:]]) ]] &&
            (echo "noetic" && git clone --recursive https://github.com/luxonis/depthai-ros.git --depth 1 -b noetic) ||
            git clone --recursive https://github.com/luxonis/depthai-ros.git --depth 1 -b humble
    fi

    echo -e "${GREEN}cd ${dir_name} ...${NC}"
    cd depthai-ros/"${dir_name}" || exit

    rosdep install --from-paths ../ --ignore-src -r -y

    version="$(sed -n '/<version>/p' package.xml | sed -E 's|.*>([0-9.].*)<.*|\1|g')"
    ros_pkg_name=ros-"${ROS_DISTRO}"-"${pkg_name}"_"${version}"

    echo -e "${GREEN}Build ${ros_pkg_name} ...${NC}"

    if [ "$(dpkg --print-architecture)" = "amd64" ] && [ "${codename}" != "buster" ]; then
        orig_tar="${ros_pkg_name}.orig.tar.xz"
        echo -e "${GREEN}Create ${orig_tar} ...${NC}"
        tar --xz -cf ../"${orig_tar}" "../${dir_name}"
    fi

    echo -e "${GREEN}Create debian files ...${NC}"
    bloom-generate rosdebian -i "${debian_inc}"
    sed -i -e "s/(${version}-${debian_inc}${codename})/(${version}-${debian_inc}${codename}~${datetime})/g" debian/changelog

    if [ "$(dpkg --print-architecture)" = "amd64" ] && [ "${codename}" != "buster" ]; then
        echo -e "${GREEN}Build ${pkg_name} source package ...${NC}"
        dpkg-buildpackage -S -j"$(nproc)"
    fi

    echo -e "${GREEN}Build ${ros_pkg_name} binary package ...${NC}"
    dpkg-buildpackage -b -j"$(nproc)" -Zgzip

    echo -e "${GREEN}Install ${ros_pkg_name} deb ... ${NC}"
    deb_name="${ros_pkg_name}-${debian_inc}${codename}~${datetime}_$(dpkg --print-architecture).deb"
    sudo apt install -qq -y ../${deb_name}

}

copy_artifacts() {
    sudo mkdir -p /workdir/artifacts/"${codename}"/
    sudo cp -u /tmp/depthai-ros/ros-"${ROS_DISTRO}"-* /workdir/artifacts/"${codename}"

}

if [ -z ${PACKAGE} ]; then
    while getopts "cfmbera" arg; do #第一个冒号表示忽略错误；字符后面的冒号表示该选项必须有自己的参数。
        case $arg in
        c)
            depthai_core
            ;;
        f)
            foxglove_msgs
            ;;
        r)
            build_package depthai_ros_msgs depthai-ros-msgs
            build_package depthai_bridge depthai-bridge
            build_package depthai_examples depthai-examples
            build_package depthai_ros_driver depthai-ros-driver
            build_package depthai-ros
            copy_artifacts
            ;;
        a)
            depthai_core
            foxglove_msgs
            build_package depthai_ros_msgs depthai-ros-msgs
            build_package depthai_bridge depthai-bridge
            build_package depthai_examples depthai-examples
            build_package depthai_ros_driver depthai-ros-driver
            build_package depthai-ros
            copy_artifacts
            ;;
        *)
            echo "pass"
            ;;
        esac

    done

else
    if [ ${PACKAGE} = 'depthai' ]; then
        depthai_core
    elif [ ${PACKAGE} = 'foxglove-msgs' ]; then
        foxglove_msgs
    elif [ ${PACKAGE} = 'depthai-ros' ]; then
        build_package depthai_ros_msgs depthai-ros-msgs
        build_package depthai_bridge depthai-bridge
        build_package depthai_examples depthai-examples
        build_package depthai_ros_driver depthai-ros-driver
        build_package depthai-ros
    elif [ ${PACKAGE} = 'all' ]; then
        depthai_core
        foxglove_msgs
        build_package depthai_ros_msgs depthai-ros-msgs
        build_package depthai_bridge depthai-bridge
        build_package depthai_examples depthai-examples
        build_package depthai_ros_driver depthai-ros-driver
        build_package depthai-ros
    fi
    copy_artifacts
fi
