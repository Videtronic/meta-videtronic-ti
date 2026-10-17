FILESEXTRAPATHS:prepend := "${THISDIR}/device-tree-overlays-ti:"

CUSTOM_OVERLAYS_SOURCE = " \
  aquila-am69-clover-gmsl2-csi1-dual-imx219.dts \
  aquila-am69-clover-gmsl2-csi1-single-imx219.dts \
  aquila-am69-clover-gmsl2-csi1-quad-ov5640.dts \
  aquila-am69-clover-gmsl2-csi2-quad-ov5640.dts \
  aquila-am69-clover-gmsl2-csi1-quad-imx219.dts \
  aquila-am69-clover-gmsl2-csi2-quad-imx219.dts \
  aquila-am69-clover-csi1-imx219.dts \
  aquila-am69-clover-csi2-imx219.dts \
  aquila-am69-clover-rtos-memory-map.dts \
"

CUSTOM_OVERLAYS_BINARY = " \
  aquila-am69-clover-gmsl2-csi1-dual-imx219.dtbo \
  aquila-am69-clover-gmsl2-csi1-single-imx219.dtbo \
  aquila-am69-clover-gmsl2-csi1-quad-ov5640.dtbo \
  aquila-am69-clover-gmsl2-csi2-quad-ov5640.dtbo \
  aquila-am69-clover-gmsl2-csi1-quad-imx219.dtbo \
  aquila-am69-clover-gmsl2-csi2-quad-imx219.dtbo \
  aquila-am69-clover-csi1-imx219.dtbo \
  aquila-am69-clover-csi2-imx219.dtbo \
  aquila-am69-clover-rtos-memory-map.dtbo \
"

SRC_URI += " \
  file://aquila-am69-clover-gmsl2-csi1-dual-imx219.dts \
  file://aquila-am69-clover-gmsl2-csi1-single-imx219.dts \
  file://aquila-am69-clover-gmsl2-csi1-quad-ov5640.dts \
  file://aquila-am69-clover-gmsl2-csi2-quad-ov5640.dts \
  file://aquila-am69-clover-gmsl2-csi1-quad-imx219.dts \
  file://aquila-am69-clover-gmsl2-csi2-quad-imx219.dts \
  file://aquila-am69-clover-csi1-imx219.dts \
  file://aquila-am69-clover-csi2-imx219.dts \
  file://aquila-am69-clover-rtos-memory-map.dts \
"

TEZI_EXTERNAL_KERNEL_DEVICETREE_BOOT:aquila-am69 = " \
  aquila-am69-clover-rtos-memory-map.dtbo \
"

do_collect_overlays:prepend() {
    for DTS in ${CUSTOM_OVERLAYS_SOURCE}; do
        cp ${WORKDIR}/${DTS} ${S}
    done
}