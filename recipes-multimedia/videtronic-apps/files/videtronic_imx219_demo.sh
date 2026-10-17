#!/bin/bash
#
# IMX219 demo - route the media graph for every IMX219 present, then show them
# as a mosaic (or stream them, see --net).
#
# Replaces the separate 1x/2x/4x scripts: the camera count is discovered at
# runtime and the mosaic layout follows from it. Both wiring variants work:
#
#   GMSL2:  imx219 -> max96717 -> max96724 -> cdns csi-bridge -> ticsi2rx
#   direct: imx219 -> cdns csi-bridge -> ticsi2rx
#
# The serdes path needs explicit routes on every subdev (each stream is tagged
# with a virtual channel); the direct path only needs matching formats. Either
# way the IMX219 delivers raw Bayer, so frames go through tiovxisp before use.
#
# Companion overlays:
#   aquila-am69-clover-gmsl2-csi1-quad-imx219.dtbo    (4x GMSL2)
#   aquila-am69-clover-gmsl2-csi1-dual-imx219.dtbo    (2x GMSL2)
#   aquila-am69-clover-gmsl2-csi1-single-imx219.dtbo  (1x GMSL2)
#   aquila-am69-clover-csi1-imx219.dtbo               (1x directly attached)
#
# Bring-up is racy: a capture device can be left streaming by a pipeline that
# died, and the media graph takes a moment to settle after vision_apps_init.
# This script releases the devices, verifies each step, and retries the whole
# setup rather than assuming a fixed sleep was long enough.

# NOTE: deliberately not 'set -e'. Every command that matters is checked
# explicitly so it can report *what* failed instead of exiting silently.
set -o pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NOCOLOR='\033[0m'

IMX219_CAM_FMT="${IMX219_CAM_FMT:-[fmt:SRGGB8_1X8/1920x1080 field: none]}"
FPS="${FPS:-20}"
TILE_WIDTH="${TILE_WIDTH:-640}"
TILE_HEIGHT="${TILE_HEIGHT:-480}"
SINK="${SINK:-waylandsink fullscreen=false}"
ATTEMPTS="${ATTEMPTS:-3}"
MEDIA_ID="${MEDIA_ID:-0}"
DCC_DIR="${DCC_DIR:-/opt/imaging/imx219/linear}"

# --net streaming defaults
STREAM_HOST="${STREAM_HOST:-}"
STREAM_PORT="${STREAM_PORT:-5000}"
BITRATE="${BITRATE:-8000000}"
MTU="${MTU:-1400}"

VERBOSE=0
SETUP_ONLY=0
NET=0
DUMP_GRAPH=0
INTERRUPTED=0
WANT_CAMS=0          # 0 = accept whatever is found

# filled in by setup_imx219()
NUM_CAMS=0
declare -a CAM_KIND
declare -A ALL_MAX96724_FMT_STR
declare -A ALL_CDNS_FMT_STR
declare -A ALL_CSI2RX_FMT_STR
declare -A CSI2RX_NEXT_PAD
declare -A CSI2RX_NEXT_CTX

# ---------------------------------------------------------------- logging ---

info(){ echo -e "${GREEN}$*${NOCOLOR}"; }
warn(){ echo -e "${YELLOW}warning: $*${NOCOLOR}" >&2; }
err(){  echo -e "${RED}error: $*${NOCOLOR}" >&2; }
dbg(){  [ "$VERBOSE" -eq 1 ] && echo -e "${BLUE}+ $*${NOCOLOR}" >&2; return 0; }

die(){ err "$*"; exit 1; }

usage(){
  cat >&2 <<EOF
usage: $0 [options]

  --cams N         require exactly N cameras (default: use whatever is found)
  --net [HOST]     stream the mosaic over RTP/UDP instead of showing it
                   locally. HOST is auto-detected when omitted.
  --port N         UDP port for --net (default: $STREAM_PORT)
  --bitrate BPS    H.264 bitrate for --net (default: $BITRATE)
  --setup-only     configure the media graph, then exit without streaming
  --dump-graph     print the full media graph and exit (for bug reports)
  --attempts N     retry setup up to N times (default: $ATTEMPTS)
  --verbose        echo every media-ctl command and its output
  -h, --help       this text

environment:
  SINK             gstreamer sink branch (default: "$SINK")
  FPS              capture framerate (default: $FPS)
  TILE_WIDTH       mosaic tile width (default: $TILE_WIDTH)
  TILE_HEIGHT      mosaic tile height (default: $TILE_HEIGHT)
  IMX219_CAM_FMT   subdev format string
  DCC_DIR          ISP tuning directory (default: $DCC_DIR)
  STREAM_HOST      override --net auto-detection
  STREAM_PORT      UDP port (default: $STREAM_PORT)
  BITRATE          H.264 bitrate (default: $BITRATE)

examples:
  $0                      # every camera found, on the local display
  $0 --cams 4             # fail unless exactly four are configured
  $0 --net                # stream to whoever is ssh'd in
  $0 --net 192.168.11.2 --port 5000 --bitrate 4000000
EOF
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --cams)       WANT_CAMS="${2:?--cams needs a number}"; shift 2 ;;
    --net)
      NET=1
      # optional HOST argument: take it only if it isn't another flag
      if [ -n "$2" ] && [ "${2#-}" = "$2" ]; then STREAM_HOST="$2"; shift 2; else shift; fi
      ;;
    --port)       STREAM_PORT="${2:?--port needs a number}"; shift 2 ;;
    --bitrate)    BITRATE="${2:?--bitrate needs a number}"; shift 2 ;;
    --setup-only) SETUP_ONLY=1; shift ;;
    --dump-graph) DUMP_GRAPH=1; shift ;;
    --attempts)   ATTEMPTS="${2:?--attempts needs a number}"; shift 2 ;;
    --verbose|-v) VERBOSE=1; shift ;;
    -h|--help)    usage ;;
    *)            err "unknown option: $1"; usage ;;
  esac
done

is_number(){ case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

is_number "$ATTEMPTS"  || die "--attempts must be a positive integer, got '$ATTEMPTS'"
[ "$ATTEMPTS" -lt 1 ]  && die "--attempts must be at least 1"
is_number "$WANT_CAMS" || die "--cams must be a positive integer, got '$WANT_CAMS'"

if [ "$NET" -eq 1 ]; then
  is_number "$STREAM_PORT" || die "--port must be a number, got '$STREAM_PORT'"
  [ "$STREAM_PORT" -lt 1 ] || [ "$STREAM_PORT" -gt 65535 ] && die "--port out of range: $STREAM_PORT"
  is_number "$BITRATE" || die "--bitrate must be a number (bits/s), got '$BITRATE'"
fi

trap 'INTERRUPTED=1' INT TERM

# --------------------------------------------------------- media-ctl glue ---

# Run a media-ctl command that must succeed. On failure print the exact command
# and whatever media-ctl said, which is the part the old scripts threw away.
mc(){
  local desc="$1"; shift
  local out rc
  dbg "media-ctl $*"
  out="$(media-ctl "$@" 2>&1)"; rc=$?
  if [ $rc -ne 0 ]; then
    err "$desc"
    err "  cmd: media-ctl $*"
    [ -n "$out" ] && err "  out: ${out//$'\n'/$'\n'       }"
    return 1
  fi
  [ -n "$out" ] && dbg "  -> $out"
  return 0
}

# Same, but a failure is only worth a note (used where a subdev legitimately
# inherits its format from upstream instead of accepting one).
mc_soft(){
  local desc="$1"; shift
  dbg "media-ctl $* (optional)"
  if ! media-ctl "$@" >/dev/null 2>&1; then
    dbg "note: $desc"
    return 1
  fi
  return 0
}

mcq(){ media-ctl "$@" 2>/dev/null; }
ent(){ mcq -d "$MEDIA_ID" -p -e "$1"; }

need(){
  local value="$1" what="$2"
  if [ -z "$value" ]; then
    err "could not determine $what"
    err "  (re-run with --verbose, or --dump-graph to inspect the media graph)"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------- network ---

valid_ipv4(){
  local ip="$1" a b c d o
  [ -z "$ip" ] && return 1
  case "$ip" in
    *[!0-9.]*|*..*) return 1 ;;
  esac
  IFS=. read -r a b c d <<<"$ip"
  [ -z "$a" ] || [ -z "$b" ] || [ -z "$c" ] || [ -z "$d" ] && return 1
  for o in "$a" "$b" "$c" "$d"; do
    [ "$o" -gt 255 ] 2>/dev/null && return 1
  done
  [ "$a" -eq 0 ] && return 1
  [ "$a" -eq 127 ] && return 1
  return 0
}

# The USB-C gadget link re-enumerates with a fresh MAC on every replug, so the
# host address is not stable and must not be hardcoded. Asking the ssh session
# we are already talking over is the only source that is always current.
detect_stream_host(){
  local cand n

  if [ -n "$STREAM_HOST" ]; then
    dbg "stream host given explicitly: $STREAM_HOST"
    echo "$STREAM_HOST"; return 0
  fi

  cand="$(awk '{print $1}' <<<"${SSH_CLIENT:-${SSH_CONNECTION:-}}" | sed 's/^::ffff://')"
  if valid_ipv4 "$cand"; then
    dbg "stream host from SSH_CLIENT: $cand"
    echo "$cand"; return 0
  fi

  cand="$(ip neigh show 2>/dev/null | awk '/REACHABLE|STALE|DELAY/ {print $1}' \
          | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u)"
  n="$(printf '%s\n' "$cand" | grep -c . )"
  if [ "$n" -eq 1 ] && valid_ipv4 "$cand"; then
    dbg "stream host from single arp neighbour: $cand"
    echo "$cand"; return 0
  fi

  cand="$(ip route show default 2>/dev/null | awk '{print $3; exit}')"
  if valid_ipv4 "$cand"; then
    dbg "stream host from default route: $cand"
    echo "$cand"; return 0
  fi

  if [ "$n" -gt 1 ]; then
    err "several candidate hosts found, cannot pick one automatically:"
    printf '  %s\n' $cand >&2
  fi
  return 1
}

build_net_sink(){
  printf '%s' \
    "v4l2h264enc extra-controls=\"controls,video_bitrate=$BITRATE,h264_i_frame_period=$FPS\"" \
    " ! h264parse config-interval=1" \
    " ! rtph264pay pt=96 mtu=$MTU config-interval=1" \
    " ! udpsink host=$STREAM_HOST port=$STREAM_PORT sync=false async=false"
}

print_receiver_hint(){
  echo
  info "streaming ${CANVAS_WIDTH}x${CANVAS_HEIGHT}@${FPS} H.264 to $STREAM_HOST:$STREAM_PORT (${BITRATE} bps)"
  echo "  run this on the host:"
  echo
  echo "    gst-launch-1.0 -v \\"
  echo "      udpsrc port=$STREAM_PORT caps=\"application/x-rtp,media=video,clock-rate=90000,encoding-name=H264,payload=96\" ! \\"
  echo "      rtpjitterbuffer latency=50 ! rtph264depay ! h264parse ! avdec_h264 ! \\"
  echo "      videoconvert ! autovideosink sync=false"
  echo
}

setup_network(){
  local host
  if ! host="$(detect_stream_host)"; then
    err "could not work out where to stream to"
    err "  pass one explicitly: $0 --net <HOST-IP>"
    err "  or set STREAM_HOST=<ip> in the environment"
    return 1
  fi
  STREAM_HOST="$host"

  valid_ipv4 "$STREAM_HOST" || { err "'$STREAM_HOST' is not a usable IPv4 address"; return 1; }

  # Not fatal: the host may simply drop icmp, and udp is connectionless anyway.
  if command -v ping >/dev/null 2>&1; then
    if ! ping -c1 -W1 "$STREAM_HOST" >/dev/null 2>&1; then
      warn "$STREAM_HOST does not answer ping - streaming anyway"
      warn "  if nothing arrives, check the host firewall and that the ip is current"
    fi
  fi

  SINK="$(build_net_sink)"
  dbg "SINK=$SINK"
  return 0
}

# ------------------------------------------------------------- preflight ---

preflight(){
  local missing=0 tool
  for tool in media-ctl yavta gst-launch-1.0; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      err "required tool not found: $tool"
      missing=1
    fi
  done
  [ $missing -eq 1 ] && return 1

  if [ ! -e "/dev/media$MEDIA_ID" ]; then
    err "/dev/media$MEDIA_ID does not exist - is a camera overlay loaded?"
    return 1
  fi

  if [ ! -d "$DCC_DIR" ]; then
    err "ISP tuning directory not found: $DCC_DIR"
    err "  tiovxisp needs dcc_viss_1920x1080.bin and dcc_2a_1920x1080.bin"
    return 1
  fi

  # Streaming needs the VPU; fail early with a clear reason rather than letting
  # gstreamer report a confusing negotiation error later.
  if [[ "$SINK" == *v4l2h264enc* ]] && [ ! -e /dev/video-enc0 ]; then
    err "SINK uses v4l2h264enc but /dev/video-enc0 is missing"
    err "  check: dmesg | grep -i wave5   (needs cnm-wave-fw + kernel-module-wave5)"
    return 1
  fi
  return 0
}

# Wait until the media graph is populated. Replaces the old fixed 'sleep 0.2',
# which was the most likely cause of intermittent bring-up failures.
wait_for_graph(){
  local timeout="${1:-10}" i
  for ((i = 0; i < timeout * 10; i++)); do
    if [ -e "/dev/media$MEDIA_ID" ] && mcq -d "$MEDIA_ID" -p | grep -q imx219; then
      dbg "media graph ready after $((i * 100))ms"
      return 0
    fi
    sleep 0.1
  done
  err "media graph did not enumerate any imx219 entity within ${timeout}s"
  return 1
}

wait_for_path(){
  local path="$1" timeout="${2:-5}" i
  for ((i = 0; i < timeout * 10; i++)); do
    [ -e "$path" ] && return 0
    sleep 0.1
  done
  return 1
}

# A pipeline that died can leave a capture device streaming, which makes the
# next run fail with -EBUSY or a bogus negotiation error. Free them up.
release_devices(){
  local pids leftover i
  pids="$(lsof -t /dev/video* 2>/dev/null | sort -u | tr '\n' ' ')"
  [ -z "${pids// /}" ] && return 0

  warn "capture devices still held by pid(s): $pids"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null

  for ((i = 0; i < 30; i++)); do
    leftover="$(lsof -t /dev/video* 2>/dev/null | sort -u | tr '\n' ' ')"
    [ -z "${leftover// /}" ] && { info "released capture devices"; return 0; }
    sleep 0.1
  done

  warn "pid(s) $leftover did not exit, sending SIGKILL"
  # shellcheck disable=SC2086
  kill -9 $leftover 2>/dev/null
  sleep 0.3
  return 0
}

reset_state(){
  release_devices
  rm -f /dev/video-imx219-cam[0-9]* /dev/v4l-imx219-subdev[0-9]* 2>/dev/null
  ALL_MAX96724_FMT_STR=()
  ALL_CDNS_FMT_STR=()
  ALL_CSI2RX_FMT_STR=()
  CSI2RX_NEXT_PAD=()
  CSI2RX_NEXT_CTX=()
  CAM_KIND=()
  NUM_CAMS=0
  return 0
}

list_imx219_entities(){
  mcq -d "$MEDIA_ID" -p | grep entity | grep imx219 | cut -d ' ' -f 5
}

# ------------------------------------------------------------ setup steps ---

# A directly attached sensor occupies stream 0 and normally needs no routing,
# but the bridge and receiver still have to agree on the format. Their pads are
# only addressable as 0/0 when the driver exposes streams, so failing to set a
# format there is a note, not an error.
setup_one_direct(){
  local name="$1" idx="$2"
  local bridge csi2rx

  bridge="$(ent "imx219 $name" | grep csi-bridge | cut -d '"' -f 2)"
  need "$bridge" "the csi-bridge for directly attached 'imx219 $name'" || return 1
  csi2rx="$(ent "$bridge" | grep 'ticsi2rx"' | cut -d '"' -f 2)"
  need "$csi2rx" "the ticsi2rx behind '$bridge'" || return 1

  mc "failed to set the sensor format on 'imx219 $name'" \
     -d "$MEDIA_ID" -V "'imx219 $name':0 $IMX219_CAM_FMT" || return 1

  mc_soft "'$bridge' takes its format from the sensor" \
     -d "$MEDIA_ID" -V "'$bridge':0/0 $IMX219_CAM_FMT"
  mc_soft "'$csi2rx' takes its format from the bridge" \
     -d "$MEDIA_ID" -V "'$csi2rx':0/0 $IMX219_CAM_FMT"

  CAM_KIND[$idx]="direct"
  CSI2RX_OUT="$csi2rx"
  CTX_OUT="${CSI2RX_NEXT_CTX[$MEDIA_ID,$csi2rx]:-0}"
  CSI2RX_NEXT_CTX[$MEDIA_ID,$csi2rx]=$((CTX_OUT + 1))
  return 0
}

setup_one_gmsl(){
  local name="$1" idx="$2" ser="$3"
  local des des_pad bridge csi2rx next_pad ctx addr pad_select
  local fmt_des fmt_cdns fmt_csi

  mc "failed to set the max96717 route for 'imx219 $name'" \
     -d "$MEDIA_ID" --set-route "'$ser' [0/0 -> 1/0 [0x01]]" || return 1
  mc "failed to set the sensor format on 'imx219 $name'" \
     -d "$MEDIA_ID" -V "'imx219 $name':0 $IMX219_CAM_FMT" || return 1
  mc "failed to set the serializer format on '$ser'" \
     -d "$MEDIA_ID" -V "'$ser':0 $IMX219_CAM_FMT" || return 1

  des="$(ent "$ser" | grep max96724 | cut -d '"' -f 2)"
  need "$des" "the max96724 deserializer behind '$ser'" || return 1
  des_pad="$(ent "$ser" | grep max96724 | cut -d : -f 2 | awk '{print $1}')"
  need "$des_pad" "the max96724 pad for '$ser'" || return 1

  bridge="$(ent "$des" | grep csi-bridge | cut -d '"' -f 2)"
  need "$bridge" "the csi-bridge behind '$des'" || return 1
  csi2rx="$(ent "$bridge" | grep 'ticsi2rx"' | cut -d '"' -f 2)"
  need "$csi2rx" "the ticsi2rx behind '$bridge'" || return 1

  next_pad="${CSI2RX_NEXT_PAD[$MEDIA_ID,$csi2rx]:-1}"
  ctx="${CSI2RX_NEXT_CTX[$MEDIA_ID,$csi2rx]:-0}"

  # 4500000 - CSI1 brings the streams out on pad 6, the others on pad 4
  addr="$(cut -d'.' -f1 <<<"$csi2rx")"
  if [ "$addr" = "4500000" ]; then pad_select=6; else pad_select=4; fi

  fmt_des="${des_pad}/0 -> ${pad_select}/${next_pad} [1]"
  fmt_cdns="0/${next_pad} -> 1/${next_pad} [1]"
  fmt_csi="0/${next_pad} -> ${next_pad}/0 [1]"

  CSI2RX_NEXT_PAD[$MEDIA_ID,$csi2rx]=$((next_pad + 1))
  CSI2RX_NEXT_CTX[$MEDIA_ID,$csi2rx]=$((ctx + 1))

  if [ -v "ALL_MAX96724_FMT_STR[$MEDIA_ID,$des]" ]; then
    ALL_MAX96724_FMT_STR[$MEDIA_ID,$des]="${ALL_MAX96724_FMT_STR[$MEDIA_ID,$des]}, $fmt_des"
  else
    ALL_MAX96724_FMT_STR[$MEDIA_ID,$des]="$fmt_des"
  fi
  if [ -v "ALL_CDNS_FMT_STR[$MEDIA_ID,$bridge]" ]; then
    ALL_CDNS_FMT_STR[$MEDIA_ID,$bridge]="${ALL_CDNS_FMT_STR[$MEDIA_ID,$bridge]}, $fmt_cdns"
  else
    ALL_CDNS_FMT_STR[$MEDIA_ID,$bridge]="$fmt_cdns"
  fi
  if [ -v "ALL_CSI2RX_FMT_STR[$MEDIA_ID,$csi2rx]" ]; then
    ALL_CSI2RX_FMT_STR[$MEDIA_ID,$csi2rx]="${ALL_CSI2RX_FMT_STR[$MEDIA_ID,$csi2rx]}, $fmt_csi"
  else
    ALL_CSI2RX_FMT_STR[$MEDIA_ID,$csi2rx]="$fmt_csi"
  fi

  CAM_KIND[$idx]="gmsl2"
  CSI2RX_OUT="$csi2rx"
  CTX_OUT="$ctx"
  return 0
}

setup_imx219(){
  local count=0 name ser subdev dev dev_name subdev_name res fmt kind

  for name in $(list_imx219_entities); do
    ser="$(ent "imx219 $name" | grep max96717 | cut -d '"' -f 2)"
    subdev="$(ent "imx219 $name" | grep v4l-subdev | awk '{print $4}')"
    need "$subdev" "the v4l-subdev node for 'imx219 $name'" || return 1

    CSI2RX_OUT=""; CTX_OUT=""
    if [ -n "$ser" ]; then
      setup_one_gmsl "$name" "$count" "$ser" || return 1
    else
      setup_one_direct "$name" "$count" || return 1
    fi

    dev="$(ent "$CSI2RX_OUT context $CTX_OUT" | grep video | awk '{print $4}')"
    if [ -z "$dev" ]; then
      err "no /dev/video node for '$CSI2RX_OUT context $CTX_OUT' (camera $count)"
      err "  the ticsi2rx context entity exists but exposes no video device"
      return 1
    fi
    if [ ! -e "$dev" ]; then
      err "'$CSI2RX_OUT context $CTX_OUT' reports $dev but that node does not exist"
      return 1
    fi

    dev_name="/dev/video-imx219-cam$count"
    subdev_name="/dev/v4l-imx219-subdev$count"
    ln -snf "$dev" "$dev_name"       || { err "failed to link $dev_name -> $dev"; return 1; }
    ln -snf "$subdev" "$subdev_name" || { err "failed to link $subdev_name -> $subdev"; return 1; }

    res="$(echo "$IMX219_CAM_FMT" | cut -d / -f 2 | cut -d ' ' -f 1)"
    fmt="$(echo "$IMX219_CAM_FMT" | cut -d : -f 2 | cut -d _ -f 1)"
    dbg "yavta -s $res -f $fmt $dev"
    if ! yavta -s "$res" -f "$fmt" "$dev" >/dev/null 2>&1; then
      err "yavta failed to set $fmt/$res on $dev (camera $count)"
      err "  the device is usually still streaming from an earlier run"
      return 1
    fi

    kind="${CAM_KIND[$count]}"
    info "IMX219 Camera $count detected ($kind)"
    echo "    device = $dev_name -> $dev"
    echo "    name = imx219 $name"
    echo "    format = $IMX219_CAM_FMT"
    echo "    subdev_id = $subdev_name -> $subdev"
    echo "    receiver = $CSI2RX_OUT context $CTX_OUT"

    count=$((count + 1))
  done

  NUM_CAMS=$count

  if [ "$count" -eq 0 ]; then
    err "no IMX219 cameras could be configured"
    err "  the media graph has no imx219 entity, or none of them are wired up"
    return 1
  fi
  if [ "$WANT_CAMS" -gt 0 ] && [ "$count" -ne "$WANT_CAMS" ]; then
    err "--cams $WANT_CAMS requested but $count configured"
    return 1
  fi
  return 0
}

setup_routes(){
  local i id name ser des des_pad csi_pad bridge csi2rx

  # Only GMSL2 paths need routing; a graph of directly attached sensors leaves
  # all three arrays empty and these loops do nothing.

  for i in "${!ALL_MAX96724_FMT_STR[@]}"; do
    id="$(cut -d',' -f1 <<<"$i")"
    name="$(cut -d',' -f2 <<<"$i")"
    mc "failed to program routes on deserializer '$name'" \
       -d "$id" -R "'$name' [${ALL_MAX96724_FMT_STR[$i]}]" || return 1

    for name in $(list_imx219_entities); do
      ser="$(ent "imx219 $name" | grep max96717 | cut -d '"' -f 2)"
      [ -z "$ser" ] && continue
      des="$(ent "$ser" | grep max96724 | cut -d '"' -f 2)"
      des_pad="$(ent "$ser" | grep max96724 | cut -d : -f 2 | awk '{print $1}')"
      need "$des" "the max96724 for '$ser' while setting formats" || return 1
      need "$des_pad" "the max96724 pad for '$ser' while setting formats" || return 1
      mc "failed to set format on '$des':$des_pad" \
         -d "$id" -V "'$des':$des_pad $IMX219_CAM_FMT" || return 1
    done
  done

  for i in "${!ALL_CDNS_FMT_STR[@]}"; do
    id="$(cut -d',' -f1 <<<"$i")"
    name="$(cut -d',' -f2 <<<"$i")"
    mc "failed to program routes on csi-bridge '$name'" \
       -d "$id" -R "'$name' [${ALL_CDNS_FMT_STR[$i]}]" || return 1

    for name in $(list_imx219_entities); do
      ser="$(ent "imx219 $name" | grep max96717 | cut -d '"' -f 2)"
      [ -z "$ser" ] && continue
      des="$(ent "$ser" | grep max96724 | cut -d '"' -f 2)"
      des_pad="$(ent "$ser" | grep max96724 | cut -d : -f 2 | awk '{print $1}')"
      csi_pad="$(ent "$des" | grep "$des_pad/.*[ACTIVE]" | cut -d '/' -f 3 | awk '{print $1}')"
      bridge="$(ent "$des" | grep csi-bridge | cut -d '"' -f 2)"
      need "$csi_pad" "the active csi pad on '$des' pad $des_pad" || return 1
      need "$bridge" "the csi-bridge for '$des'" || return 1
      mc "failed to set format on '$bridge':0/$csi_pad" \
         -d "$id" -V "'$bridge':0/$csi_pad $IMX219_CAM_FMT" || return 1
    done
  done

  for i in "${!ALL_CSI2RX_FMT_STR[@]}"; do
    id="$(cut -d',' -f1 <<<"$i")"
    name="$(cut -d',' -f2 <<<"$i")"
    csi2rx="$name"
    mc "failed to program routes on ticsi2rx '$name'" \
       -d "$id" -R "'$name' [${ALL_CSI2RX_FMT_STR[$i]}]" || return 1

    for name in $(list_imx219_entities); do
      ser="$(ent "imx219 $name" | grep max96717 | cut -d '"' -f 2)"
      [ -z "$ser" ] && continue
      des="$(ent "$ser" | grep max96724 | cut -d '"' -f 2)"
      des_pad="$(ent "$ser" | grep max96724 | cut -d : -f 2 | awk '{print $1}')"
      csi_pad="$(ent "$des" | grep "$des_pad/.*[ACTIVE]" | cut -d '/' -f 3 | awk '{print $1}')"
      need "$csi_pad" "the active csi pad on '$des' pad $des_pad" || return 1
      mc "failed to set format on '$csi2rx':0/$csi_pad" \
         -d "$id" -V "'$csi2rx':0/$csi_pad $IMX219_CAM_FMT" || return 1
    done
  done

  return 0
}

verify_cams(){
  local i missing=0
  for ((i = 0; i < NUM_CAMS; i++)); do
    wait_for_path "/dev/video-imx219-cam$i" 3 || { err "/dev/video-imx219-cam$i is missing after setup"; missing=1; }
    wait_for_path "/dev/v4l-imx219-subdev$i" 3 || { err "/dev/v4l-imx219-subdev$i is missing after setup"; missing=1; }
  done
  [ $missing -eq 1 ] && return 1
  return 0
}

setup_all(){
  reset_state
  wait_for_graph 10 || return 1
  setup_imx219   || return 1
  setup_routes   || return 1
  verify_cams    || return 1
  return 0
}

# ---------------------------------------------------------------- layout ---

# Smallest square-ish grid that holds NUM_CAMS tiles:
#   1 -> 1x1, 2 -> 2x1, 3/4 -> 2x2, 5..9 -> 3x3
compute_layout(){
  COLS=1
  while [ $((COLS * COLS)) -lt "$NUM_CAMS" ]; do COLS=$((COLS + 1)); done
  ROWS=$(( (NUM_CAMS + COLS - 1) / COLS ))
  CANVAS_WIDTH=$((COLS * TILE_WIDTH))
  CANVAS_HEIGHT=$((ROWS * TILE_HEIGHT))
  dbg "layout: ${NUM_CAMS} cams -> ${COLS}x${ROWS} grid, canvas ${CANVAS_WIDTH}x${CANVAS_HEIGHT}"
}

# -------------------------------------------------------------- pipeline ---

isp_branch(){
  # $1 = camera index, $2 = tiovxmosaic sink pad
  echo "\
  v4l2src device=/dev/video-imx219-cam$1 io-mode=5 ! queue max-size-buffers=1 leaky=2 ! \
  video/x-bayer,width=1920,height=1080,framerate=$FPS/1,format=rggb ! \
  tiovxisp sink_0::device=/dev/v4l-imx219-subdev$1 sensor-name=SENSOR_SONY_IMX219_RPI \
  dcc-isp-file=$DCC_DIR/dcc_viss_1920x1080.bin \
  sink_0::dcc-2a-file=$DCC_DIR/dcc_2a_1920x1080.bin format-msb=7 ! \
  video/x-raw,format=NV12 ! queue ! $2"
}

build_pipeline(){
  local i col row parts=""

  for ((i = 0; i < NUM_CAMS; i++)); do
    parts="$parts $(isp_branch "$i" "mosaic.sink_$i")"
  done

  parts="$parts tiovxmosaic name=mosaic"
  for ((i = 0; i < NUM_CAMS; i++)); do
    col=$((i % COLS))
    row=$((i / COLS))
    parts="$parts sink_$i::startx=\"<$((col * TILE_WIDTH))>\""
    parts="$parts sink_$i::starty=\"<$((row * TILE_HEIGHT))>\""
    parts="$parts sink_$i::widths=\"<$TILE_WIDTH>\""
    parts="$parts sink_$i::heights=\"<$TILE_HEIGHT>\""
  done

  parts="$parts ! videoscale !"
  parts="$parts video/x-raw,format=NV12,width=$CANVAS_WIDTH,height=$CANVAS_HEIGHT !"
  parts="$parts $SINK"

  echo "$parts"
}

run_pipeline(){
  local pipeline
  pipeline="$(build_pipeline)"
  dbg "gst-launch-1.0 $pipeline"
  eval gst-launch-1.0 "$pipeline"
}

# A pipeline that dies within a few seconds means the hardware was left in a bad
# state; re-running setup usually clears it. One that ran for a while and then
# stopped was almost certainly Ctrl-C, so don't fight the user.
run_with_retry(){
  local attempt start elapsed rc
  for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
    [ "$INTERRUPTED" -eq 1 ] && return 130

    info "starting pipeline (attempt $attempt/$ATTEMPTS)"
    start=$SECONDS
    run_pipeline
    rc=$?
    elapsed=$((SECONDS - start))

    [ "$INTERRUPTED" -eq 1 ] && { echo; info "interrupted"; return 0; }
    [ $rc -eq 0 ] && return 0

    if [ $elapsed -ge 5 ]; then
      err "pipeline exited with status $rc after ${elapsed}s"
      return $rc
    fi

    warn "pipeline failed after ${elapsed}s (status $rc) - re-running setup"
    if [ $attempt -lt "$ATTEMPTS" ]; then
      sleep 1
      setup_all || { err "setup failed while recovering"; return 1; }
      compute_layout
    fi
  done

  err "pipeline failed $ATTEMPTS times"
  err "  try: $0 --dump-graph   and check dmesg for csi/serdes errors"
  return 1
}

# ------------------------------------------------------------------ main ---

main(){
  if [ "$NET" -eq 1 ]; then
    setup_network || exit 1
  fi

  preflight || exit 1

  if [ -f /opt/vision_apps/vision_apps_init.sh ]; then
    dbg "sourcing /opt/vision_apps/vision_apps_init.sh"
    # shellcheck disable=SC1091
    source /opt/vision_apps/vision_apps_init.sh >/dev/null 2>&1
  else
    warn "/opt/vision_apps/vision_apps_init.sh not found - tiovx elements may fail"
  fi

  if [ "$DUMP_GRAPH" -eq 1 ]; then
    wait_for_graph 10 || exit 1
    media-ctl -d "$MEDIA_ID" -p
    exit 0
  fi

  local attempt
  for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
    [ "$INTERRUPTED" -eq 1 ] && exit 130
    info "configuring media graph (attempt $attempt/$ATTEMPTS)"
    if setup_all; then
      info "$NUM_CAMS camera(s) configured"
      break
    fi
    if [ "$attempt" -eq "$ATTEMPTS" ]; then
      err "media graph setup failed after $ATTEMPTS attempts"
      err "  try: $0 --verbose      to see which media-ctl call fails"
      err "  try: $0 --dump-graph   to inspect the graph"
      err "  also check: dmesg | tail -40"
      exit 1
    fi
    warn "setup failed, retrying in 1s"
    sleep 1
  done

  compute_layout

  if [ "$SETUP_ONLY" -eq 1 ]; then
    info "--setup-only given, not streaming"
    exit 0
  fi

  [ "$NET" -eq 1 ] && print_receiver_hint

  run_with_retry
  exit $?
}

main "$@"
