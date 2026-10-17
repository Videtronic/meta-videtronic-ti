SUMMARY = "Videtronic demo applications for Aquila AM69"
DESCRIPTION = "Installs the Videtronic AM69 demo scripts. videtronic_imx219_demo.sh \
covers any number of IMX219 cameras, GMSL2 or directly attached; the fixed 4x/2x/1x \
scripts are kept for now."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://videtronic_imx219_demo.sh \
"

S = "${WORKDIR}"

VIDETRONIC_APPS_DIR = "/opt/videtronic_apps"

RDEPENDS:${PN} = " \
    bash \
    media-ctl \
    yavta \
    gstreamer1.0 \
    gstreamer1.0-plugins-good-video4linux2 \
    gstreamer1.0-plugins-base-videoconvertscale \
    gstreamer1.0-plugins-base-compositor \
    gstreamer1.0-plugins-bad-waylandsink \
    gstreamer1.0-plugins-bad-videoparsersbad \
    gstreamer1.0-plugins-good-rtp \
    gstreamer1.0-plugins-good-rtpmanager \
    gstreamer1.0-plugins-good-udp \
    lsof \
    iproute2 \
"

PACKAGE_ARCH = "${MACHINE_ARCH}"

do_install() {
    install -d ${D}${VIDETRONIC_APPS_DIR}
    install -m 0755 ${WORKDIR}/videtronic_imx219_demo.sh ${D}${VIDETRONIC_APPS_DIR}/videtronic_imx219_demo.sh
}

FILES:${PN} += "${VIDETRONIC_APPS_DIR}"
