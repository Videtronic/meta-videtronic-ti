FILESEXTRAPATHS:prepend := "${THISDIR}/linux-toradex-ti:"

SRC_URI += "\
        file://maxim-serdes.cfg \
        file://0001-media-i2c-ds90ub960-Replace-aliased-clients-list-wit.patch \
        file://0002-media-i2c-ds90ub960-Protect-alias_use_mask-with-a-mu.patch \
        file://0003-i2c-use-client-addresses-directly-in-ATR-interface.patch \
        file://0004-i2c-move-ATR-alias-pool-to-a-separate-struct.patch \
        file://0005-i2c-rename-field-alias_list-of-struct-i2c_atr_chan-t.patch \
        file://0006-i2c-support-per-channel-ATR-alias-pools.patch \
        file://0007-i2c-Support-dynamic-address-translation.patch \
        file://0008-locking-mutex-Introduce-mutex_init_with_key.patch \
        file://0009-i2c-atr-Fix-lockdep-for-nested-ATRs.patch \
        file://0010-i2c-atr-find_mapping-get_mapping.patch \
        file://0011-i2c-atr-split-up-i2c_atr_get_mapping_by_addr.patch \
        file://0012-i2c-atr-do-not-create-mapping-in-detach_addr.patch \
        file://0013-i2c-atr-deduplicate-logic-in-attach_addr.patch \
        file://0014-i2c-atr-allow-replacing-mappings-in-attach_addr.patch \
        file://0015-i2c-atr-add-flags-parameter-to-i2c_atr_new.patch \
        file://0016-i2c-atr-add-static-flag.patch \
        file://0017-i2c-atr-add-passthrough-flag.patch \
        file://0020-regmap-provide-regmap_assign_bits.patch \
        file://0021-i2c-mux-Remove-class-argument-from-i2c_mux_add_adapt.patch \
        file://0022-media-v4l-Support-passing-media-pad-argument-to-v4l2.patch \
        file://0023-media-v4l-Support-obtaining-link-frequency-via-get_m.patch \
        file://0033-arm64-defconfig-disable-deprecated-MAX96712-driver.patch \
        file://0034-staging-media-remove-MAX96712-driver.patch \
        file://0037-i2c-omap-Increase-timeout-to-5-seconds.patch \
        file://0038-media-cadence-csi2rx-Support-reading-link-frequency-.patch \
        file://0039-media-i2c-add-backported-GMSL2-serdes-drivers.patch \
        file://0040-media-i2c-imx219-implement-configurable-VC-via-devic.patch \
        file://0041-media-i2c-ov5640-implement-configurable-VC-via-devic.patch \
        file://0042-arm64-dts-ti-k3-am69-aquila-add-missing-r5fss0_core0.patch \
        file://0047-drivers-remoteproc-ti_sci_proc-add-ti_sci_proc_of_ge.patch \
        file://0043-i2c-omap-recover-the-bus-after-a-controller-timeout.patch \
        file://ti_k3_r5_remoteproc.c \
"

do_patch:prepend() {
    rm -f ${S}/drivers/remoteproc/ti_k3_r5_remoteproc.c
    cp ${WORKDIR}/ti_k3_r5_remoteproc.c ${S}/drivers/remoteproc/ti_k3_r5_remoteproc.c
}

### file://0050-drivers-remoteproc-k3-r5-remove-current-driver.patch
### file://0051-drivers-remoteproc-use-6.12-implementation.patch 
### file://0052-drivers-remoteproc-k3-r5-apply-Check-mailbox-before-.patch 