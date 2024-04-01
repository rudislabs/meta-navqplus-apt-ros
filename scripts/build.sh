#!/bin/bash
# This script is designed to run in container.

BUILD_TYPE=humble
BRANCH=imx-6.1.22-$BUILD_TYPE

MANIFEST="imx-6.1.22-2.0.0_desktop.xml"
DISTRO="imx-desktop-xwayland"
SETUP="imx-setup-desktop.sh"
IMGNAME="imx-image-desktop"
BUILDRECIPES="imx-image-desktop navq-install-desktop imx-image-desktop-ros"
BUILDDIR="build-desktop"
BBMASK=""
PACKAGING="rpm"

BUILD_OUTPUT="built-images"

BUILD=`date +%Y%m%d.%H%M`; start=`date +%s`

mkdir -p /home/user/work/$BUILD_OUTPUT
mkdir -p /home/user/work/$BUILDDIR
cd /home/user/work/$BUILDDIR

# Init

repo init \
    -u https://github.com/nxp-imx/imx-manifest.git \
    -b imx-linux-mickledore \
    -m ${MANIFEST}

repo sync -j`nproc`

get_yocto_hash() {
    local githash=$(git rev-parse --short=10 HEAD)
    echo "$githash"
}

get_yocto_info() {
    local githash=$(get_yocto_hash)
    local val=$(echo "yocto-distro aarch64 x.x.x+git0+$githash-r0")
    echo "$val"
}

mkdir tmp
pushd tmp

for i in u-boot-imx linux-imx meta-navqplus-apt-ros; do
    if [ -d ${i} ]; then
        pushd ${i}
        git pull
        popd
    else
        git clone -b $BRANCH git@github.com:rudislabs/${i}.git || exit $?
    fi
    if [ $i = "meta-navqplus-apt-ros" ]; then
        pushd $i
            yocto_hash=$(get_yocto_hash)
            yocto_info=$(get_yocto_info)
        popd
    fi
done

popd # tmp

pushd sources
rm -f meta-navqplus-apt-ros && ln -s ../tmp/meta-navqplus-apt-ros . || exit $?
git clone -b mickledore https://github.com/sbabic/meta-swupdate.git
popd # sources
RELEASE_VER="${BUILD_TYPE}-$(date +%y%m%d%H%M%S)-${yocto_hash}"

DISTRO=${DISTRO} MACHINE=imx8mpnavq EULA=yes BUILD_DIR=builddir source ./${SETUP} || exit $?

sed -i 's/^DL_DIR.*$/DL_DIR\ \?=\ \"\/home\/cache\/CACHE\/6.1.22\/downloads\/\"/' conf/local.conf || exit $?
echo "SSTATE_DIR = \"/home/cache/CACHE/6.1.22/sstate-cache\"" >> conf/local.conf || exit $?
echo "BBMASK += \"$BBMASK\"" >> conf/local.conf || exit $?

# Don't build gstreamer curl plugin, to remove dependency of libcurl,
# to avoid installing duplicate libraries.
echo "PACKAGECONFIG:remove:pn-gstreamer1.0-plugins-bad = \"curl\"" >> conf/local.conf || exit $?

sed -i -e "s/BB_DEFAULT_UMASK =/BB_DEFAULT_UMASK ?=/" ../sources/poky/meta/conf/bitbake.conf
sed -i -e "s/PACKAGE_CLASSES ?\?=.*$/PACKAGE_CLASSES ?= \"package_$PACKAGING\"/" conf/local.conf

echo BBLAYERS += \"\${BSPDIR}/sources/meta-navqplus-apt-ros\" >> conf/bblayers.conf || exit $?
echo BBLAYERS += \"\${BSPDIR}/sources/meta-swupdate\" >> conf/bblayers.conf || exit $?

echo $RELEASE_VER > ${BUILDDIR}/../sources/meta-navqplus-apt-ros/recipes-fsl/images/files/release || exit $?

for i in ${BUILDDIR}/../sources/meta-navqplus-apt-ros/recipes-bsp/u-boot/u-boot-imx_2023.04.bbappend \
     ${BUILDDIR}/../sources/meta-navqplus-apt-ros/recipes-kernel/linux/linux-imx_6.1.bbappend;
do
    sed -i "s/^LOCALVERSION\s*=.*/LOCALVERSION = \"-${RELEASE_VER}\"/" ${i}
    if [ "x$(grep '^LOCALVERSION\s*=' ${i})" = "x" ]; then
        echo "LOCALVERSION = \"-$RELEASE_VER\"" >> ${i} || exit $?
    fi
done

export BB_ENV_PASSTHROUGH_ADDITIONS="PACKAGE_CLASSES"
bitbake uuu-native -c cleansstate
bitbake ${BUILDRECIPES} uuu-native || exit $?
# Only builds with package_ipk
PACKAGE_CLASSES="package_ipk" bitbake navq-swu || exit $?

echo "$yocto_info" >> $BUILDDIR/tmp/deploy/images/imx8mpnavq/$IMGNAME-imx8mpnavq.manifest || exit $?

files=(
    Image
    imx8mp-navq.dtb
    imx-boot-imx8mpnavq-sd.bin-flash_evk
    imx-image-desktop-imx8mpnavq.tar.zst
    imx-image-desktop-imx8mpnavq.wic.zst
    imx-image-full-imx8mpnavq.tar.zst
    imx-image-full-imx8mpnavq.wic.zst
    uuu
    navq-dbg.uuu
    navq-install-desktop.uuu
    navq-install.uuu
    navq-install-initrd.uImage
    navq-install-desktop-initrd.uImage
    partitions.sfdisk
)

ros_files=(
    imx-image-desktop-ros-imx8mpnavq.wic.zst
)

echo -e "\n\nMOVING FILES\n\n"

if [ -d "/home/user/work/$BUILD_OUTPUT" ]; then
    mkdir -p /home/user/work/$BUILD_OUTPUT/$RELEASE_VER
    for i in ${files[*]} ${ros_files[*]}; do
        file=$BUILDDIR/tmp/deploy/images/imx8mpnavq/$i
        echo -e "$file ->"
        if [ -f $file ]; then
            cp $file /home/user/work/$BUILD_OUTPUT/$RELEASE_VER/$i
            echo -e "/home/user/work/$BUILD_OUTPUT/$RELEASE_VER/$i"
        fi
    done
fi

finish=`date +%s`; echo "### Build Time = `expr \( $finish - $start \) / 60` minutes"
