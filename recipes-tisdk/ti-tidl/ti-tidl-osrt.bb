SUMMARY = "Open Source DL/ML runtime Modules"
DESCRIPTION = "Open Source DL/ML runtime Modules like TF-LITE and ONNX Runtime, NEO-AI-DLR. Supports both Python and CPP APIs"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

S = "${WORKDIR}/src"
PR:append = "_edgeai_4"
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
LICENSE = "MIT"

SRC_URI = "https://software-dl.ti.com/jacinto7/esd/tidl-tools/11_00_00_00/OSRT_TOOLS/ARM_LINUX/ARAGO/dlr-1.13.0-py3-none-any.whl;name=dlr;subdir=${S}/dlr\
           https://software-dl.ti.com/jacinto7/esd/tidl-tools/11_00_00_00/OSRT_TOOLS/ARM_LINUX/ARAGO/tflite_runtime-2.12.0-cp312-cp312-linux_aarch64.whl;name=tflite;subdir=${S}/tflite\
           https://software-dl.ti.com/jacinto7/esd/tidl-tools/11_00_00_00/OSRT_TOOLS/ARM_LINUX/ARAGO/onnxruntime_tidl-1.15.0-cp312-cp312-linux_aarch64.whl;name=ort;subdir=${S}/ort\
           https://software-dl.ti.com/jacinto7/esd/tidl-tools/11_00_00_00/OSRT_TOOLS/ARM_LINUX/ARAGO/tflite_2.12_aragoj7.tar.gz;name=tfl_lib;subdir=${S}/tfl_lib\
           https://software-dl.ti.com/jacinto7/esd/tidl-tools/11_00_00_00/OSRT_TOOLS/ARM_LINUX/ARAGO/onnx_1.15.0_aragoj7.tar.gz;name=ort_lib;subdir=${S}/ort_lib\
           https://software-dl.ti.com/jacinto7/esd/tidl-tools/11_00_00_00/OSRT_TOOLS/ARM_LINUX/ARAGO/opencv_4.2.0_aragoj7.tar.gz;name=opencv;subdir=${S}/opencv\
"
SRC_URI[dlr.sha256sum] = "141a7ab29684ddb9c227964575bfb1a4e532b7786cc5cbd49bf4b68269fbe7db"
SRC_URI[tflite.sha256sum] = "94c5f0ccbd5458cfa1327b378c7d479dc7d23979df8f26f091720f850dc02364"
SRC_URI[ort.sha256sum] = "7a8011a5ca3f5d0d83cfe2a5ec92a60f97e7e5587a49babcf06e55ef50479b7e"
SRC_URI[tfl_lib.sha256sum] = "2ff6878f51595395d84830747da6a8ddbb168eab93e84edd9e5f75cfb33b6b55"
SRC_URI[ort_lib.sha256sum] = "0c4ef38355d1b04030b7370a44837b719a1d052359948803710c4e45a67a8c1b"
SRC_URI[opencv.sha256sum] = "4122073c37e3dd268fa814b6a53510325a1e6636aa3aea9d02ab79f42b4355bd"

do_cp_downloaded_build_deps() {
    mv ${S}/tfl_lib/*/* ${S}/tfl_lib
    mv ${S}/ort_lib/*/* ${S}/ort_lib
    mv ${S}/opencv/*/* ${S}/opencv
}
addtask cp_downloaded_build_deps after do_unpack before do_patch

DEPENDS += "unzip-native"

COMPATIBLE_MACHINE = "j721e|j721s2|j784s4|j722s|j742s2|am62axx"

inherit python3-dir

FILES:${PN}-staticdev += "${libdir}/tflite_2.12/"
FILES:${PN} += "${libdir}/*.so*"
FILES:${PN} += "${PYTHON_SITEPACKAGES_DIR}/*"
FILES:${PN} += "${includedir}"
FILES:${PN} += "/usr/dlr/"

do_install() {
    install -d ${D}${PYTHON_SITEPACKAGES_DIR}
    unzip -d ${D}${PYTHON_SITEPACKAGES_DIR} ${S}/tflite/tflite_runtime-2.12.0-cp312-cp312-linux_aarch64.whl
    unzip -d ${D}${PYTHON_SITEPACKAGES_DIR} ${S}/dlr/dlr-1.13.0-py3-none-any.whl
    unzip -d ${D}${PYTHON_SITEPACKAGES_DIR} ${S}/ort/onnxruntime_tidl-1.15.0-cp312-cp312-linux_aarch64.whl

    install -d ${D}${includedir}
    install -d ${D}${libdir}

    cp -r ${S}/tfl_lib/tensorflow  ${D}${includedir}/
    cp -r ${S}/tfl_lib/tflite_2.12  ${D}${libdir}/
    cp ${S}/tfl_lib/libtensorflow-lite.a ${D}${libdir}/

    cp   ${S}/ort_lib/libonnxruntime.so.1.15.0  ${D}${libdir}/
    ln -s -r ${D}${libdir}/libonnxruntime.so.1.15.0 ${D}${libdir}/libonnxruntime.so
    rm -rf  ${S}/ort_lib/onnxruntime/csharp
    cp -r  ${S}/ort_lib/onnxruntime ${D}${includedir}/

    cp -r ${S}/opencv/opencv-4.2.0  ${D}${includedir}/

    mkdir -p ${D}/usr/dlr
    ln -s -r ${D}${PYTHON_SITEPACKAGES_DIR}/dlr/libdlr.so ${D}${libdir}/libdlr.so
}

