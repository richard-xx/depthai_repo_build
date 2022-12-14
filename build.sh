#!/bin/env bash

GREEN='\033[0;32m'
NC='\033[0m'
datetime=$(date +%Y%m%d)
# GREEN=' '
# NC=' '
debian_inc="3"

codename=$(lsb_release -c -s)
sudo mkdir -p /workdir/artifacts/"${codename}"/

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
        env BUILD_TESTING_ARG="-DOpenCV_DIR=/home/ubuntu/OpenCV4.2/lib/cmake/opencv4" dpkg-buildpackage -b -j"$(nproc)"
    else
        dpkg-buildpackage -b -j"$(nproc)"
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
    dpkg-buildpackage -b -j"$(nproc)"

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
        git clone --recursive https://github.com/luxonis/depthai-ros.git --depth 1 -b ros-release
    fi

    echo -e "${GREEN}cd ${dir_name} ...${NC}"
    cd depthai-ros/"${dir_name}" || exit

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
    dpkg-buildpackage -b -j"$(nproc)"

    echo -e "${GREEN}Install ${ros_pkg_name} deb ... ${NC}"
    deb_name="${ros_pkg_name}-${debian_inc}${codename}~${datetime}_$(dpkg --print-architecture).deb"
    sudo apt install -qq -y ../${deb_name}

}

copy_artifacts() {
    sudo mkdir -p /workdir/artifacts/"${codename}"/
    sudo cp -u /tmp/depthai-ros/ros-"${ROS_DISTRO}"-* /workdir/artifacts/"${codename}"

}

while getopts "cfmbera" arg; do #???????????????????????????????????????????????????????????????????????????????????????????????????
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
        build_package depthai-ros
        copy_artifacts
        ;;
    a)
        depthai_core
        foxglove_msgs
        build_package depthai_ros_msgs depthai-ros-msgs
        build_package depthai_bridge depthai-bridge
        build_package depthai_examples depthai-examples
        build_package depthai-ros
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
