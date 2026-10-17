# meta-videtronic-ti

Yocto layer that adds GMSL2 camera support and the TI Vision Apps / EdgeAI
imaging stack to the **Toradex Aquila AM69** (TI J784S4) on the **Toradex
Clover** carrier board. It plugs into the standard Toradex BSP 7 (Yocto
*scarthgap*) build and provides:

- Device tree overlays for IMX219 and OV5640 cameras, either attached directly
  to a Clover CSI connector or over GMSL2 (MAX96717 serializer → MAX96724
  deserializer).
- Kernel patches for `linux-toradex-ti`: backported Maxim GMSL2 serdes drivers,
  I2C address translator (ATR) support, virtual channel support for IMX219 and
  OV5640, and i2c-omap fixes needed to bring up four GMSL2 cameras reliably.
- The TI Vision Apps / TIOVX / EdgeAI stack (firmware, `tiovxisp`,
  `tiovxmosaic` and other GStreamer elements, TIDL runtimes), plus the memory
  map overlay that stack needs.
- `videtronic-reference-multimedia-image`, a Toradex reference multimedia image
  with all of the above and the Videtronic demo script.

The IMX219 and OV5640 sensors here are third-party reference cameras, not
Videtronic products. They were used to bring up and validate the GMSL2 path
(MAX96717 serializer → MAX96724 deserializer → CSI-2 → TI ISP).

Everything in this document was tested on an Aquila AM69 on a Clover carrier
board, with four IMX219 cameras over GMSL2 on CSI1.

## Contents

1. [Dependencies](#1-dependencies)
2. [Set up the Toradex BSP](#2-set-up-the-toradex-bsp)
3. [Add meta-videtronic-ti](#3-add-meta-videtronic-ti)
4. [Build the Videtronic image](#4-build-the-videtronic-image)
5. [Flash the board](#5-flash-the-board)
6. [Enable a camera overlay](#6-enable-a-camera-overlay)
7. [Run the 4x IMX219 demo](#7-run-the-4x-imx219-demo)
8. [Stream to a host PC](#8-stream-to-a-host-pc)
9. [Troubleshooting](#9-troubleshooting)
10. [Layer contents](#10-layer-contents)
11. [Licensing](#11-licensing)

## 1. Dependencies

This layer sits on top of the Toradex reference BSP (`scarthgap-7.x.y`
manifest). It depends on these layers, which come with that manifest:

| Layer | Repository | Branch |
|---|---|---|
| openembedded-core | https://git.openembedded.org/openembedded-core | scarthgap |
| meta-toradex-ti | https://git.toradex.com/meta-toradex-ti.git | scarthgap-7.x.y |
| meta-toradex-bsp-common | https://git.toradex.com/meta-toradex-bsp-common.git | scarthgap-7.x.y |
| meta-toradex-distro | https://git.toradex.com/meta-toradex-distro.git | scarthgap-7.x.y |
| meta-toradex-demos | https://git.toradex.com/meta-toradex-demos.git | scarthgap-7.x.y |
| meta-ti (meta-ti-bsp, meta-ti-extras) | https://git.yoctoproject.org/meta-ti | scarthgap |
| meta-arm | https://git.yoctoproject.org/meta-arm | scarthgap |

You do not need `meta-edgeai` or the TI Processor SDK: this layer carries its
own recipes for the TI components (`recipes-tisdk/`), pinned to PSDK 11.x.

## 2. Set up the Toradex BSP

Follow Toradex's *Build a Reference Image with Yocto Project/OpenEmbedded* guide
to prepare the host (packages, `repo`, disk space). In short:

```sh
mkdir -p ~/yocto-toradex && cd ~/yocto-toradex
repo init -u https://git.toradex.com/toradex-manifest.git \
          -b scarthgap-7.x.y -m tdxref/default.xml
repo sync
```

This gives you a workspace like this:

```
yocto-toradex/
├── export          # build environment setup script (from meta-toradex-distro)
└── layers/
    ├── openembedded-core
    ├── meta-toradex-ti
    ├── meta-ti
    └── ...
```

## 3. Add meta-videtronic-ti

### 3.1 Get the layer

Clone it next to the other layers:

```sh
cd ~/yocto-toradex/layers
git clone -b scarthgap https://github.com/Videtronic/meta-videtronic-ti.git
```

If you prefer `repo` to manage it, add a local manifest instead, so that
`repo sync` keeps it up to date with the rest:

```xml
<!-- ~/yocto-toradex/.repo/local_manifests/videtronic.xml -->
<manifest>
  <remote name="videtronic" fetch="https://github.com/Videtronic"/>
  <project name="meta-videtronic-ti" path="layers/meta-videtronic-ti"
           remote="videtronic" revision="scarthgap"/>
</manifest>
```

### 3.2 Create the build directory

```sh
cd ~/yocto-toradex
. export
```

The first run creates `build/conf/local.conf` and `build/conf/bblayers.conf`
and leaves you in `build/`. In later shells, run `. export` again to get the
build environment back.

### 3.3 Register the layer

From `build/`:

```sh
bitbake-layers add-layer ../layers/meta-videtronic-ti
```

Or add it to `BBLAYERS` in `build/conf/bblayers.conf` by hand. A path relative
to `${TOPDIR}` keeps the build directory movable, for example into a container:

```
BBLAYERS ?= " \
  ...
  ${TOPDIR}/../layers/openembedded-core/meta \
  ${TOPDIR}/../layers/meta-videtronic-ti \
"
```

Check that it is picked up:

```sh
bitbake-layers show-layers | grep videtronic
```

### 3.4 Select the machine

In `build/conf/local.conf`:

```
MACHINE ?= "aquila-am69"
```

Leave the rest of the generated `local.conf` alone. In particular, keep the
`DEPLOY_DIR` / `TI_COMMON_DEPLOY` lines, which the TI multiconfig build
(`aquila-am69-k3r5`) needs.

## 4. Build the Videtronic image

**Build `videtronic-reference-multimedia-image`.** It is the Toradex
`tdx-reference-multimedia-image` with everything the cameras need added on
top:

- TI Vision Apps, the EdgeAI R5F/C7x firmware and TIOVX, which provide
  `tiovxisp` (debayering and ISP) and `tiovxmosaic`.
- TIDL and the open-source DL runtimes.
- `yavta`, `media-ctl` and the Videtronic demo script in `/opt/videtronic_apps`.

The stock Toradex images build and boot with this layer and include the camera
overlays and kernel drivers. They do not include the TI imaging stack, though,
so the demo will not run on them.

```sh
cd ~/yocto-toradex/build
bitbake videtronic-reference-multimedia-image
```

The first build fetches and compiles the whole TI stack and takes a long time.
It needs noticeably more disk space than the minimal image. Later builds reuse
`downloads/` and `sstate-cache/`.

The result is a Toradex Easy Installer package in
`build/deploy/images/aquila-am69/`:

```
Aquila-AM69_Videtronic-Reference-Multimedia-Image-Tezi_<version>.tar
```

## 5. Flash the board

Flash the board with the **Toradex Easy Installer** (Tezi), as you would any
Toradex reference image:

1. Extract the `-Tezi_<version>.tar` onto a FAT32 USB stick:
   `tar xf Aquila-AM69_Videtronic-Reference-Multimedia-Image-Tezi_*.tar -C /media/<usb>`
2. Boot the Aquila AM69 into Toradex Easy Installer (recovery mode, see the
   Toradex documentation for the Clover recovery procedure).
3. Plug in the stick and install *Videtronic Reference Multimedia Image*.

After the first boot you can reach the board over:

- the debug UART on Clover, or
- SSH over the USB-C device port: the board is `192.168.11.1`, and your PC gets
  an address on `192.168.11.0/24` by DHCP.

```sh
ssh root@192.168.11.1
```

## 6. Enable a camera overlay

The image always enables `aquila-am69-clover-rtos-memory-map.dtbo`, which
reserves memory for the Vision Apps firmware. **The camera overlay is not
enabled by default.** Pick the one that matches your setup:

| Overlay | Setup |
|---|---|
| `aquila-am69-clover-gmsl2-csi1-quad-imx219.dtbo` | 4x IMX219 over GMSL2, deserializer on CSI1 |
| `aquila-am69-clover-gmsl2-csi1-dual-imx219.dtbo` | 2x IMX219 over GMSL2 (links A, B), CSI1 |
| `aquila-am69-clover-gmsl2-csi1-single-imx219.dtbo` | 1x IMX219 over GMSL2 (link A), CSI1 |
| `aquila-am69-clover-gmsl2-csi2-quad-imx219.dtbo` | 4x IMX219 over GMSL2, deserializer on CSI2 |
| `aquila-am69-clover-gmsl2-csi1-quad-ov5640.dtbo` | 4x OV5640 over GMSL2, CSI1 |
| `aquila-am69-clover-gmsl2-csi2-quad-ov5640.dtbo` | 4x OV5640 over GMSL2, CSI2 |
| `aquila-am69-clover-csi1-imx219.dtbo` | 1x IMX219 directly on CSI1 |
| `aquila-am69-clover-csi2-imx219.dtbo` | 1x IMX219 directly on CSI2 |

Enable only one camera overlay per CSI port.

### At runtime (quickest)

Edit `/boot/overlays.txt` on the board. Keep the memory map overlay in the
list and add the camera overlay:

```
fdt_overlays=aquila-am69-clover-rtos-memory-map.dtbo aquila-am69-clover-gmsl2-csi1-quad-imx219.dtbo
```

Then `reboot`.

### At build time

To get an image with the overlay already enabled, add this to
`build/conf/local.conf` and rebuild the image:

```
TEZI_EXTERNAL_KERNEL_DEVICETREE_BOOT:append:pn-device-tree-overlays-ti = " aquila-am69-clover-gmsl2-csi1-quad-imx219.dtbo"
```

### Check the cameras probed

```sh
dmesg | grep -iE 'imx219|max9672|max96717'
media-ctl -p | grep entity
```

With the quad overlay you should see four `imx219` entities, four `max96717`
serializers and one `max96724` deserializer.

## 7. Run the 4x IMX219 demo

The demo script finds every IMX219 in the media graph, routes the GMSL2 or
direct CSI path, runs each stream through the TI ISP (`tiovxisp`) and puts
them together in a single mosaic (`tiovxmosaic`). The camera count is detected
at runtime, so the same script handles 1, 2 or 4 cameras. Four cameras give a
2x2 grid of 640x480 tiles (1280x960) at 20 fps on the local Wayland display:

```sh
/opt/videtronic_apps/videtronic_imx219_demo.sh
```

To fail unless exactly four cameras come up:

```sh
/opt/videtronic_apps/videtronic_imx219_demo.sh --cams 4
```

Stop it with `Ctrl-C`.

Useful options (see `--help` for all of them):

| Option / variable | Meaning |
|---|---|
| `--cams N` | require exactly N cameras |
| `--net [HOST]` | stream over RTP/UDP instead of the local display (see below) |
| `--setup-only` | configure the media graph and exit, for use with your own pipeline |
| `--dump-graph` | print the media graph and exit (attach this to bug reports) |
| `--verbose` | print every `media-ctl` command and its output |
| `FPS`, `TILE_WIDTH`, `TILE_HEIGHT` | capture rate and mosaic tile size |
| `SINK` | replace the GStreamer sink, e.g. `SINK=fakesink` |

After `--setup-only`, the cameras are available as `/dev/video-imx219-cam<N>`
and `/dev/v4l-imx219-subdev<N>`, which you can use in your own GStreamer
pipelines.

## 8. Stream to a host PC

With `--net`, the mosaic is encoded to H.264 by the AM69 hardware encoder and
sent as RTP over UDP. If you start the script from an SSH session, it sends to
the machine you are connected from, so it works over the USB-C link with no
configuration:

```sh
# on the board
/opt/videtronic_apps/videtronic_imx219_demo.sh --net
# or with an explicit host, port and bitrate
/opt/videtronic_apps/videtronic_imx219_demo.sh --net 192.168.11.89 --port 5000 --bitrate 4000000
```

The script prints the matching receiver command. On the host, with GStreamer
and `gstreamer1.0-libav` installed:

```sh
gst-launch-1.0 -v \
  udpsrc port=5000 caps="application/x-rtp,media=video,clock-rate=90000,encoding-name=H264,payload=96" ! \
  rtpjitterbuffer latency=50 ! rtph264depay ! h264parse ! avdec_h264 ! \
  videoconvert ! autovideosink sync=false
```

Start the receiver before or after the board, either order works. Make sure no
older receiver is still running: `udpsrc` binds with `reuse=true`, so a stale
one silently takes the packets. Check with `ss -ulpn | grep 5000`.

## 9. Troubleshooting

- **First start fails, a retry works.** Camera bring-up is racy. The script
  retries setup itself (`--attempts N`, default 3). If it still fails, run the
  whole script again rather than re-running a bare `gst-launch-1.0`, because
  the media graph has to be routed again.
- **`/dev/media0 does not exist`.** No camera overlay is loaded. Check
  `/boot/overlays.txt` and `dmesg`.
- **`omap_i2c ... controller timed out` in dmesg.** This layer includes a fix
  (`0043-i2c-omap-recover-the-bus-after-a-controller-timeout.patch`). If you
  still see it, check the GMSL2 cables and the camera PoC supply.
- **`tiovx` elements fail to start.** Check that
  `aquila-am69-clover-rtos-memory-map.dtbo` is still in `/boot/overlays.txt`
  and that the remote cores are up: `dmesg | grep -i remoteproc`.
- **No `/dev/video-enc0` with `--net`.** The Wave5 encoder did not probe:
  `dmesg | grep -i wave5`.
- **`not-negotiated` after adding `videoscale` to a pipeline.** `videoscale`
  cannot sit directly on a `tiovxisp` source pad. Put it after `tiovxmosaic`
  or use `tiovxmultiscaler`.

For bug reports, include `--dump-graph` output, `dmesg`, and the script output
with `--verbose`.

## 10. Layer contents

```
conf/layer.conf
recipes-images/images/
    videtronic-reference-multimedia-image.bb    image to build
recipes-kernel/linux/
    linux-toradex-ti_%.bbappend                 kernel patches + maxim-serdes.cfg
    linux-toradex-ti/                           patches, R5F remoteproc driver
    device-tree-overlays-ti_git.bbappend        builds the Clover overlays
    device-tree-overlays-ti/                    overlay sources (.dts)
recipes-multimedia/
    videtronic-apps/                            demo script -> /opt/videtronic_apps
    gstreamer/                                  gstreamer1.0-plugins-bad: kms
recipes-tisdk/
    ti-psdk-rtos/                               ti-vision-apps, ti-edgeai-firmware
    edgeai-components/                          tiovx kernels/modules, edgeai-gst-plugins, ...
    ti-tidl/                                    TIDL and OSRT runtimes
```

Kernel changes on top of `linux-toradex-ti`:

- **I2C ATR and GMSL2 serdes:** backported I2C address translator rework, plus
  the upstream Maxim serdes framework (MAX96717, MAX96724, MAX9296A, ...). The
  old staging MAX96712 driver is removed.
- **V4L2:** streams-aware `get_mbus_config` and link frequency handling, used
  by `cdns-csi2rx`. IMX219 and OV5640 get a configurable virtual channel from
  the device tree.
- **i2c-omap:** longer timeout, and bus recovery after a controller timeout,
  so that four GMSL2 cameras probe reliably.
- **Remoteproc:** an updated K3 R5F remoteproc driver and an Aquila DT fix for
  `r5fss0_core0`, so that the Vision Apps firmware loads.

## 11. Licensing

The layer's own files (recipes, scripts, configuration) are released under the
MIT license, see [COPYING.MIT](COPYING.MIT). Kernel patches and device tree
overlays are GPL-2.0 (overlays are dual GPL-2.0-or-later OR MIT, see each
file's SPDX header).

The components fetched by the `recipes-tisdk/` recipes come from Texas
Instruments under their own licenses, mostly TI-TFL. See the `LICENSE` field
of each recipe and the license of each fetched source.

## Maintainer

Videtronic, support@videtronic.com