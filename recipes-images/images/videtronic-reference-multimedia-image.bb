require recipes-images/images/tdx-reference-multimedia-image.bb

SUMMARY = "Videtronic Reference Multimedia Image"
DESCRIPTION = "Image for BSP verification with QT, multimedia and TI EdgeAI features"

APP_LAUNCH_WAYLAND = ""

#Prefix to the resulting deployable tarball name
export IMAGE_BASENAME = "Videtronic-Reference-Multimedia-Image"

IMAGE_INSTALL += " \
  ti-vision-apps \
  ti-edgeai-firmware \
  ti-tidl \
  ti-tidl-osrt \
  edgeai-apps-utils \
  edgeai-dl-inferer \
  edgeai-tiovx-kernels \
  edgeai-tiovx-modules \
  edgeai-gst-plugins \
  yavta \
  videtronic-apps \
"