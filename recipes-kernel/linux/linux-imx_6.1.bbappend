FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI = "git://github.com/rudislabs/linux-imx.git;protocol=https;branch=imx-6.1.22-vb;nobranch=1"
SRCREV = "${AUTOREV}"

SRC_URI += " \
    file://cp21xx.cfg \
    file://ov5645tn.cfg \
    file://tja1xxc45.cfg \
    file://pcf2131.cfg \
    file://gasket_apex.cfg \
    file://mrvl_bt.cfg \
    file://RISCV-31-increase-hci-timeout.patch \
    file://joystick.cfg \
    file://containers.cfg \
    file://fw.cfg \
    file://ipv6.cfg \
    file://usb-serial.cfg \
    file://imx219.cfg \
    file://usbmon.cfg \
"

do_configure:append () {
    ${S}/scripts/kconfig/merge_config.sh -m -O ${B} ${B}/.config $(ls ${WORKDIR}/*.cfg)

    if [ ! -z "${LOCALVERSION}" ]; then
        echo "CONFIG_LOCALVERSION="\"${LOCALVERSION}\" >> ${B}/.config
    fi
}
