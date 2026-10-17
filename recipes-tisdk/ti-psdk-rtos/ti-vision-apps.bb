SUMMARY = "OpenVX Middleware library"
DESCRIPTION = "Builds tivision_apps user space library"

PV = "11.01.02"

LICENSE = "TI-TFL & BSD-2-Clause & BSD-3-Clause & BSD-4-Clause & MIT & Apache-2.0 & Apache-2.0-with-LLVM-exception & \
           Khronos & Hewlett-Packard & Patrick-Powell & FTL & Zlib & CC0-1.0 & OpenSSL"

LIC_FILES_CHKSUM = " \
    file://${COREBASE}/../meta-ti/meta-ti-bsp/licenses/TI-TFL;md5=a1b59cb7ba626b9dbbcbf00f3fbc438a \
    file://${COMMON_LICENSE_DIR}/BSD-2-Clause;md5=cb641bc04cda31daea161b1bc15da69f \
    file://${COMMON_LICENSE_DIR}/BSD-3-Clause;md5=550794465ba0ec5312d6919e203a55f9 \
    file://${COMMON_LICENSE_DIR}/BSD-4-Clause;md5=624d9e67e8ac41a78f6b6c2c55a83a2b \
    file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302 \
    file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10 \
    file://${COMMON_LICENSE_DIR}/Apache-2.0-with-LLVM-exception;md5=0bcd48c3bdfef0c9d9fd17726e4b7dab \
    file://${WORKDIR}/tiovx/include/VX/vx.h;beginline=1;endline=15;md5=37315206223081f32a5b9aaaf912f637 \
    file://${COREBASE}/../meta-ti/meta-ti-extras/licenses/Hewlett-Packard;md5=a07676ee09f5bfec457eb5ea75921d01 \
    file://${COREBASE}/../meta-ti/meta-ti-extras/licenses/Patrick-Powell;md5=7e10716f13cff502f3cf6ebf8fe29c1e \
    file://${COMMON_LICENSE_DIR}/FTL;md5=f0bf6b09ee8b02121ed10709d9e49d8b \
    file://${COMMON_LICENSE_DIR}/Zlib;md5=87f239f408daca8a157858e192597633 \
    file://${COMMON_LICENSE_DIR}/CC0-1.0;md5=0ceb3372c9595f0a8067e55da801e4a1 \
    file://${COREBASE}/meta/files/common-licenses/OpenSSL;md5=4eb1764f3e65fafa1a25057f9082f2ae \
"

BRANCH="main"
SRC_URI = " \
    git://git.ti.com/git/processor-sdk/sdk_builder.git;protocol=https;branch=${BRANCH};destsuffix=sdk_builder;name=sdk_builder \
    git://git.ti.com/git/processor-sdk/app_utils.git;protocol=https;branch=${BRANCH};destsuffix=app_utils;name=app_utils \
    git://git.ti.com/git/processor-sdk/vision_apps.git;protocol=https;branch=${BRANCH};destsuffix=vision_apps;name=vision_apps \
    git://git.ti.com/git/processor-sdk/tiovx.git;protocol=https;branch=${BRANCH};destsuffix=tiovx;name=tiovx \
    git://git.ti.com/git/processor-sdk/psdk_include.git;protocol=https;branch=${BRANCH};destsuffix=psdk_include;name=psdk_include \
    git://git.ti.com/git/processor-sdk/imaging.git;protocol=https;branch=${BRANCH};destsuffix=imaging;name=imaging \
    git://git.ti.com/git/processor-sdk/video_io.git;protocol=https;branch=${BRANCH};destsuffix=video_io;name=video_io \
    git://git.ti.com/git/processor-sdk/ti-perception-toolkit.git;protocol=https;branch=${BRANCH};destsuffix=ti-perception-toolkit;name=ti-perception-toolkit \
    git://git.ti.com/git/processor-sdk-vision/arm-tidl.git;protocol=https;branch=master;destsuffix=psdk_include/tidl_j7/arm-tidl;name=arm-tidl \
    git://git.ti.com/git/processor-sdk/concerto.git;protocol=https;branch=${BRANCH};destsuffix=sdk_builder/concerto;name=concerto \
"

SRCREV_FORMAT = "sdk_builder_app_utils_vision_apps_tiovx_imaging_video_io_ti-perception-toolkit_psdk_include_arm-tidl_concerto"

SRCREV_sdk_builder = "REL.PSDK.ANALYTICS.AM62A.11.01.00.05"
SRCREV_app_utils = "REL.PSDK.ANALYTICS.AM62A.11.01.00.05"
SRCREV_vision_apps = "REL.PSDK.ANALYTICS.AM62A.11.01.00.05"
SRCREV_tiovx = "REL.PSDK.ANALYTICS.AM62A.11.01.00.05"
SRCREV_imaging = "REL.PSDK.ANALYTICS.AM62A.11.01.00.05"
SRCREV_video_io = "REL.PSDK.ANALYTICS.AM62A.11.01.00.05"
SRCREV_ti-perception-toolkit = "REL.PSDK.ANALYTICS.AM62A.11.01.00.05"
SRCREV_psdk_include = "REL.PSDK.ANALYTICS.AM62A.11.01.00.05" 
SRCREV_arm-tidl = "REL.PSDK.ANALYTICS.AM62A.11.01.00.05"
SRCREV_concerto = "REL.PSDK.ANALYTICS.AM62A.11.01.00.05"

FILES:${PN} += "/opt/*"

DEPENDS = "glm freetype ti-rpmsg-char virtual/egl libpam"

COMPATIBLE_MACHINE = "j784s4"

PLAT_SOC = ""
PLAT_SOC:j784s4 = "j784s4"

S = "${WORKDIR}/sdk_builder"

CLEANBROKEN = "1"

do_compile() {
    oe_runmake \
    CROSS_COMPILE_LINARO=${TARGET_PREFIX} \
    BUILD_EMULATION_MODE=no \
    BUILD_TARGET_MODE=yes \
    BUILD_LINUX_MPU=yes \
    CONCERTO_ROOT=${S}/concerto \
    LINUX_SYSROOT_ARM=${STAGING_DIR_TARGET} \
    TREAT_WARNINGS_AS_ERROR=0 \
    GCC_LINUX_ARM_ROOT= \
    GCC_LINUX_ARM_ROOT_A72= \
    LINUX_FS_PATH=${STAGING_DIR_TARGET} \
    SOC=${PLAT_SOC} \
    yocto_build
}

do_install() {
    oe_runmake SOC=${PLAT_SOC} LINUX_FS_STAGE_PATH=${D} yocto_install
}

INSANE_SKIP:${PN} += "ldflags buildpaths"
