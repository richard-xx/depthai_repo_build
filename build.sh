#!/bin/env bash

GREEN='\033[0;32m'
NC='\033[0m'
datetime=$(date +%Y%m%d)
# GREEN=' '
# NC=' '
debian_inc="3"

codename=$(lsb_release -c -s)
sudo mkdir -p /workdir/artifacts/"${codename}"/
function depthai_core() {
    dir_name="depthai-core"
    pkg_name="depthai"

    printf "${GREEN}Clone %s ...${NC}\n" "${dir_name}"
    git clone --recursive https://github.com/luxonis/depthai-core.git --depth 1 -b ros-release

    cd depthai-core || exit

    if [ "${ROS_DISTRO}" = "kinetic" ]; then
        printf "${GREEN}Patch for %s ...${NC}\n" "${codename}"
        git apply /workdir/xenial_package.diff
    fi

    printf "${GREEN}Delete vcs files ...${NC}\n"
    rm -rf ./.git
    rm -rf ./*/*/.git

    version="$(sed -n '/<version>/p' package.xml | sed -E 's|.*>([0-9.].*)<.*|\1|g')"
    ros_pkg_name=ros-"${ROS_DISTRO}"-"${pkg_name}"_"${version}"

    printf "${GREEN}Build %s ...${NC}\n" "${ros_pkg_name}"

    if [ "$(dpkg --print-architecture)" = "amd64" ] && [ "${codename}" != "buster" ]; then
        orig_tar="${ros_pkg_name}.orig.tar.xz"
        printf "${GREEN}Create %s ...${NC}\n" "${orig_tar}"
        tar --xz -cf ../"${orig_tar}" "../${dir_name}"
    fi

    printf "${GREEN}Create debian files ...${NC}\n"
    bloom-generate rosdebian -i "${debian_inc}"
    cp /workdir/postinst_depthai_core debian/postinst
    
    if [ "$(dpkg --print-architecture)" = "amd64" ] && [ "${codename}" != "buster" ]; then
        printf "${GREEN}Build %s source package ...${NC}\n" "${pkg_name}"
        dpkg-buildpackage -S -j"$(nproc)"
    fi

    printf "${GREEN}Build %s binary package ...${NC}\n" "${ros_pkg_name}"
    if [ "${ROS_DISTRO}" = "kinetic" ] || [ "${ROS_DISTRO}" = "melodic" ] || [ "${codename}" = "buster" ]; then
        env BUILD_TESTING_ARG="-DOpenCV_DIR=/home/ubuntu/OpenCV4.2/lib/cmake/opencv4" dpkg-buildpackage -b -j"$(nproc)"
    else
        dpkg-buildpackage -b -j"$(nproc)"
    fi

    printf "${GREEN}Install %s deb ... ${NC}\n" "${ros_pkg_name}"
    sudo apt install -qq -y ../${ros_pkg_name}-${debian_inc}${codename}~${datetime}_$(dpkg --print-architecture).deb

    sudo mkdir -p /workdir/artifacts/"${codename}"/
    sudo cp -u ../ros-"${ROS_DISTRO}"-* /workdir/artifacts/"${codename}"
}

function foxglove_msgs() {
    dir_name="ros_foxglove_msgs"
    pkg_name="foxglove-msgs"

    printf "${GREEN}Clone %s ...${NC}\n" "${dir_name}"
    git clone --recursive https://github.com/foxglove/schemas.git --depth 1 -b main
    cd schemas/"${dir_name}" || exit
    
    version="$(sed -n '/<version>/p' package.xml | sed -E 's|.*>([0-9.].*)<.*|\1|g')"
    ros_pkg_name=ros-"${ROS_DISTRO}"-"${pkg_name}"_"${version}"

    printf "${GREEN}Build %s ...${NC}\n" "${ros_pkg_name}"
    
    if [ "$(dpkg --print-architecture)" = "amd64" ] && [ "${codename}" != "buster" ]; then
        orig_tar="${ros_pkg_name}.orig.tar.xz"
        printf "${GREEN}Create %s ...${NC}\n" "${orig_tar}"
        tar --xz -cf ../"${orig_tar}" "../${dir_name}"
    fi

    printf "${GREEN}Create debian files ...${NC}\n"
    bloom-generate rosdebian -i ${debian_inc}

    if [ "$(dpkg --print-architecture)" = "amd64" ] && [ "${codename}" != "buster" ]; then
        printf "${GREEN}Build %s source package ...${NC}\n" "${ros_pkg_name}"
        dpkg-buildpackage -S -j"$(nproc)"
    fi

    printf "${GREEN}Build %s binary package ...${NC}\n" "${ros_pkg_name}"
    dpkg-buildpackage -b -j"$(nproc)"

    printf "${GREEN}Install %s deb ... ${NC}\n" "${ros_pkg_name}"
    sudo apt install -qq -y ../${ros_pkg_name}-${debian_inc}${codename}~${datetime}_$(dpkg --print-architecture).deb

    sudo mkdir -p /workdir/artifacts/"${codename}"/
    sudo cp -u ../ros-"${ROS_DISTRO}"-* /workdir/artifacts/"${codename}"
}

function buildpackage() {
    dir_name="$1"
    if [ -z "$2" ]; then
        pkg_name="$1"
    else
        pkg_name="$2"
    fi

    if [ ! -f "depthai-ros" ]; then
        git clone --recursive https://github.com/luxonis/depthai-ros.git --depth 1 -b ros-release
    fi

    printf "${GREEN}cd %s ...${NC}\n" "${dir_name}"
    cd depthai-ros/"${dir_name}" || exit

    version="$(sed -n '/<version>/p' package.xml | sed -E 's|.*>([0-9.].*)<.*|\1|g')"
    ros_pkg_name=ros-"${ROS_DISTRO}"-"${pkg_name}"_"${version}"

    printf "${GREEN}Build %s ...${NC}\n" "${ros_pkg_name}"
    
    if [ "$(dpkg --print-architecture)" = "amd64" ] && [ "${codename}" != "buster" ]; then
        orig_tar="${ros_pkg_name}.orig.tar.xz"
        printf "${GREEN}Create %s ...${NC}\n" "${orig_tar}"
        tar --xz -cf ../"${orig_tar}" "../${dir_name}"
    fi

    printf "${GREEN}Create debian files ...${NC}\n"
    bloom-generate rosdebian -i "${debian_inc}"

    if [ "$(dpkg --print-architecture)" = "amd64" ] && [ "${codename}" != "buster" ]; then
        printf "${GREEN}Build %s source package ...${NC}\n" "${ros_pkg_name}"
        dpkg-buildpackage -S -j"$(nproc)"
    fi

    printf "${GREEN}Build %s binary package ...${NC}\n" "${ros_pkg_name}"
    dpkg-buildpackage -b -j"$(nproc)"

    printf "${GREEN}Install %s deb ... ${NC}\n" "${ros_pkg_name}"
    sudo apt install -qq -y ../${ros_pkg_name}-${debian_inc}${codename}~${datetime}_$(dpkg --print-architecture).deb

}

function copy_artifacts() {
    sudo mkdir -p /workdir/artifacts/"${codename}"/
    sudo cp -u /workdir/depthai-ros/ros-"${ROS_DISTRO}"-* /workdir/artifacts/"${codename}"

}

while getopts "cfmbera" arg; do #第一个冒号表示忽略错误；字符后面的冒号表示该选项必须有自己的参数。
    case $arg in
    c)
        depthai_core
        ;;
    f)
        foxglove_msgs
        ;;
    r)
        buildpackage depthai_ros_msgs depthai-ros-msgs
        buildpackage depthai_bridge depthai-bridge
        buildpackage depthai_examples depthai-examples
        buildpackage depthai-ros
        copy_artifacts
        ;;
    a)
        depthai_core
        foxglove_msgs
        buildpackage depthai_ros_msgs depthai-ros-msgs
        buildpackage depthai_bridge depthai-bridge
        buildpackage depthai_examples depthai-examples
        buildpackage depthai-ros
        copy_artifacts
        ;;
    *)
        echo "-a build all"
        echo "-c build depthai-core"
        echo "-f build foxglove-msgs"
        echo "-r build depthai-ros"
        ;;

    esac

done
