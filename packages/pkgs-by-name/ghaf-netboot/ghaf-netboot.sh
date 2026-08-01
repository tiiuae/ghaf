#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ghaf-netboot - serve a Ghaf netboot install to one machine on one interface.
#
# Pixiecore answers PXE clients in ProxyDHCP mode (it never assigns addresses,
# so it cannot disturb the lab's own DHCP), and asks our HTTP API what to do
# with each machine. The API answers 404 for anything not in --mac, so exactly
# the machine we were pointed at boots and nothing else does.
#
# Root is unavoidable: DHCP/PXE need :67, :69 and :4011, and a DHCP server must
# answer clients that have no address yet. The effort therefore goes into
# containment rather than into avoiding privilege.

usage() {
  cat <<EOF
Usage: $(basename "$0") --interface <IFACE> --mac <MAC> --netboot <DIR> --image <DIR> [options]

Serve a Ghaf netboot install. Requires root.

Required:
  -i, --interface <IFACE>  Interface facing the target. No default, deliberately.
  -m, --mac <MAC>          Target's MAC. Repeatable. Only these machines boot.
  -n, --netboot <DIR>      Result of .#<target>-netboot-installer
  -g, --image <DIR>        Result of .#<target> (ghaf-image.raw.zst + .bmap)

Options:
      --install-target <D> Install unattended to <D> (e.g. /dev/nvme0n1).
                           DESTRUCTIVE and requires --mac.
      --encrypt            With --install-target: enable disk encryption
      --secureboot         With --install-target: enroll Secure Boot keys
  -p, --port <PORT>        HTTP port (default 8080)
  -t, --timeout <MIN>      Exit after this long (default 60, 0 disables)
      --exit-after-serve   Exit once the image has been fetched once
      --force-interface    Skip the default-route / wireless refusals
      --open-firewall      Temporarily open 67/69/4011 and the HTTP ports in the
                           host firewall, and close them again on exit. Without
                           this, a host that filters inbound traffic drops every
                           PXE request before pixiecore sees it -- the server
                           looks healthy and the target times out.
      --ipxe <FILE>        64-bit UEFI iPXE binary. Defaults to pixiecore's own
                           embedded iPXE, which is the only build known to work
                           with it. Only override this if pixiecore's iPXE has
                           no driver for the NIC, and note that a stock iPXE
                           will chainload-loop: it needs an embedded script
                           that chains back to pixiecore.
      --dry-run            Print what would run and exit
  -h, --help               This message

The target must have Secure Boot OFF: the netboot chain is unsigned, exactly as
the installer ISO is. That is the same precondition the ISO's Secure Boot
enrollment already imposes, since enrollment needs firmware in Setup Mode.
EOF
}

IFACE=""
NETBOOT_DIR=""
IMAGE_DIR=""
PORT=8080
TIMEOUT_MIN=60
INSTALL_TARGET=""
ENCRYPT=false
SECUREBOOT=false
FORCE_IFACE=false
OPEN_FIREWALL=false
DRY_RUN=false
EXIT_AFTER_SERVE=false
MACS=()
# Empty by default, and package.nix deliberately does not set it: empty means
# "let pixiecore use its own embedded iPXE". Only --ipxe fills this in.
IPXE_EFI64="${IPXE_EFI64:-}"

while [ $# -gt 0 ]; do
  case "$1" in
  -i | --interface)
    IFACE="$2"
    shift 2
    ;;
  -m | --mac)
    MACS+=("$2")
    shift 2
    ;;
  -n | --netboot)
    NETBOOT_DIR="$2"
    shift 2
    ;;
  -g | --image)
    IMAGE_DIR="$2"
    shift 2
    ;;
  --install-target)
    INSTALL_TARGET="$2"
    shift 2
    ;;
  --encrypt)
    ENCRYPT=true
    shift
    ;;
  --secureboot)
    SECUREBOOT=true
    shift
    ;;
  -p | --port)
    PORT="$2"
    shift 2
    ;;
  -t | --timeout)
    TIMEOUT_MIN="$2"
    shift 2
    ;;
  --exit-after-serve)
    EXIT_AFTER_SERVE=true
    shift
    ;;
  --force-interface)
    FORCE_IFACE=true
    shift
    ;;
  --open-firewall)
    OPEN_FIREWALL=true
    shift
    ;;
  --ipxe)
    IPXE_EFI64="$2"
    shift 2
    ;;
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

die() {
  echo "ghaf-netboot: $*" >&2
  exit 1
}

# --- G0: nothing is optional, and there is no autodetect -----------------------
[ -n "$IFACE" ] || die "--interface is required (no default: picking the wrong NIC is the whole hazard)"
[ ${#MACS[@]} -gt 0 ] || die "--mac is required; without an allowlist any PXE client on this LAN would be served"
[ -n "$NETBOOT_DIR" ] || die "--netboot is required"
[ -n "$IMAGE_DIR" ] || die "--image is required"

[ -d "$NETBOOT_DIR" ] || die "no such directory: $NETBOOT_DIR"
for f in bzImage initrd netboot.ipxe; do
  [ -e "$NETBOOT_DIR/$f" ] || die "$NETBOOT_DIR/$f missing -- is that a *-netboot-installer result?"
done
[ -e "$IMAGE_DIR/ghaf-image.raw.zst" ] || die "$IMAGE_DIR/ghaf-image.raw.zst missing"
[ -e "$IMAGE_DIR/ghaf-image.bmap" ] || die "$IMAGE_DIR/ghaf-image.bmap missing (needed to verify the image)"

# Empty means "use pixiecore's own built-in iPXE", which is the right default.
# Do NOT substitute a stock iPXE here: pixiecore's embedded build carries a
# script that chains directly to pixiecore's HTTP endpoint, whereas a stock
# iPXE finishes loading and simply re-runs DHCP.
[ -z "$IPXE_EFI64" ] || [ -e "$IPXE_EFI64" ] || die "no such iPXE binary: $IPXE_EFI64"

# An unattended install wipes a disk with nobody watching. Allowlisting is not
# optional for that; it is the only thing standing between "reinstall the lab
# machine" and "reinstall whichever machine happened to PXE boot".
if [ -n "$INSTALL_TARGET" ]; then
  [[ $INSTALL_TARGET =~ ^/dev/[a-zA-Z0-9._-]+$ ]] || die "--install-target must look like /dev/nvme0n1"
fi

# --- interface guard rails ----------------------------------------------------
[ -e "/sys/class/net/$IFACE" ] || die "no such interface: $IFACE"

# G1: the single check that prevents the classic disaster.
default_iface=$(ip route show default 2>/dev/null | awk '/^default/ {print $5; exit}')
if [ -n "$default_iface" ] && [ "$default_iface" = "$IFACE" ]; then
  $FORCE_IFACE || die "$IFACE carries the default route; refusing (--force-interface to override)"
  echo "ghaf-netboot: WARNING serving on the default-route interface because --force-interface was given" >&2
fi

# G2: a wireless NIC is always the wrong answer here, and usually a typo.
if [ -d "/sys/class/net/$IFACE/wireless" ] || [ -e "/sys/class/net/$IFACE/phy80211" ]; then
  $FORCE_IFACE || die "$IFACE is wireless; refusing (--force-interface to override)"
fi

# G3: no carrier means the cable is out and nothing will boot anyway.
carrier=$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null || echo 0)
[ "$carrier" = "1" ] || die "$IFACE has no carrier; check the cable"

LISTEN_IP=$(ip -4 -br addr show "$IFACE" 2>/dev/null | awk '{print $3}' | cut -d/ -f1 | head -1)
[ -n "$LISTEN_IP" ] || die "$IFACE has no IPv4 address; give it one first"

# --- firewall ------------------------------------------------------------------
# A host that filters inbound traffic drops PXE requests before pixiecore ever
# sees them. Everything still *looks* right -- the ports are bound, the server
# says "ready" -- while the target sits there timing out, so this is worth
# handling rather than leaving as folklore.
#
# NixOS keeps a `temp-ports` set in its nixos-fw table for exactly this (it is
# what nixos-firewall-tool drives). Adding elements to it is precise and
# reversible; adding our own table would not work at all, because an `accept` in
# one nftables base chain does not stop the packet traversing another base chain
# at the same hook, so nixos-fw's `policy drop` still applies.
FW_ELEMENTS="udp . 67, udp . 69, udp . 4011, tcp . ${PORT}, tcp . $((PORT + 1))"
FW_OPENED=false

firewall_has_nixos_fw() {
  command -v nft >/dev/null 2>&1 &&
    nft list set inet nixos-fw temp-ports >/dev/null 2>&1
}

firewall_open() {
  firewall_has_nixos_fw || {
    echo "ghaf-netboot: WARNING --open-firewall: no nixos-fw temp-ports set here;" >&2
    echo "ghaf-netboot:   open $FW_ELEMENTS yourself if the target times out" >&2
    return 0
  }
  nft add element inet nixos-fw temp-ports "{ $FW_ELEMENTS }" 2>/dev/null || {
    echo "ghaf-netboot: WARNING could not open firewall ports" >&2
    return 0
  }
  FW_OPENED=true
  echo "ghaf-netboot: opened $FW_ELEMENTS (removed again on exit)" >&2
}

firewall_close() {
  $FW_OPENED || return 0
  nft delete element inet nixos-fw temp-ports "{ $FW_ELEMENTS }" 2>/dev/null ||
    echo "ghaf-netboot: WARNING could not close firewall ports; check nixos-firewall-tool show" >&2
}

# Best-effort nudge when the ports are plainly going to be dropped. Deliberately
# a warning and not a refusal: firewalls are too varied to detect reliably, and
# refusing on a false positive would be worse than a noisy line.
firewall_warn_if_closed() {
  $OPEN_FIREWALL && return 0
  command -v nft >/dev/null 2>&1 || return 0
  nft list chain inet nixos-fw input 2>/dev/null | grep -q "policy drop" || return 0
  nft list set inet nixos-fw temp-ports 2>/dev/null | grep -q "udp . 67" && return 0
  echo "ghaf-netboot: WARNING this host's firewall input policy is 'drop' and udp/67" >&2
  echo "ghaf-netboot:   is not open. PXE requests will be dropped before pixiecore" >&2
  echo "ghaf-netboot:   sees them and the target will time out with nothing logged." >&2
  echo "ghaf-netboot:   Re-run with --open-firewall." >&2
}

# --- assemble the kernel command line ----------------------------------------
# The base cmdline MUST come from the builder's own netboot.ipxe, not be written
# by hand here. It carries `init=/nix/store/...-nixos-system-.../init`, which is
# how the initrd locates the closure to switch into, plus `root=fstab` and the
# console/plymouth parameters. Passing only `ghaf.image_url=` boots a kernel that
# mounts the store and then drops to an emergency shell with
# "Failed to start Find NixOS closure" -- confirmed on hardware. The store path
# changes with every rebuild, so it has to be read at run time.
IPXE_SCRIPT="$NETBOOT_DIR/netboot.ipxe"
BASE_CMDLINE=$(awk '/^kernel /{ sub(/^kernel[[:space:]]+[^[:space:]]+[[:space:]]*/, ""); print; exit }' "$IPXE_SCRIPT")
[ -n "$BASE_CMDLINE" ] || die "could not read a 'kernel' line from $IPXE_SCRIPT"
case "$BASE_CMDLINE" in
*init=*) ;;
*) die "no init= in $IPXE_SCRIPT; the target would drop to an emergency shell" ;;
esac

# Drop the iPXE-only placeholders and the builder's own image URL: that one is
# templated on ${next-server} for a plain iPXE workflow, and we serve the image
# ourselves, so ours has to win rather than appear alongside it.
BASE_CMDLINE=$(
  printf '%s\n' "$BASE_CMDLINE" |
    sed -e 's/[$]{cmdline}//g' -e 's#ghaf[.]image_url=[^[:space:]]*##g' -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//'
)

IMAGE_URL="http://${LISTEN_IP}:${PORT}/ghaf-image"
CMDLINE="$BASE_CMDLINE ghaf.image_url=${IMAGE_URL}"
if [ -n "$INSTALL_TARGET" ]; then
  CMDLINE="$CMDLINE ghaf.install_target=${INSTALL_TARGET}"
  $ENCRYPT && CMDLINE="$CMDLINE ghaf.install_encrypt"
  $SECUREBOOT && CMDLINE="$CMDLINE ghaf.install_secureboot"
fi

cat >&2 <<EOF
ghaf-netboot:
  interface   $IFACE ($LISTEN_IP)
  allowlist   ${MACS[*]}
  netboot     $NETBOOT_DIR
  image       $IMAGE_DIR
  http        http://${LISTEN_IP}:${PORT}
  ipxe        ${IPXE_EFI64:-pixiecore built-in (correct default; a stock iPXE loops)}
  cmdline     $CMDLINE
  mode        $(if [ -n "$INSTALL_TARGET" ]; then echo "UNATTENDED INSTALL to $INSTALL_TARGET (destructive)"; else echo "interactive TUI"; fi)
  timeout     $(if [ "$TIMEOUT_MIN" = 0 ]; then echo "none"; else echo "${TIMEOUT_MIN} min"; fi)
EOF

firewall_warn_if_closed

if $DRY_RUN; then
  echo "ghaf-netboot: --dry-run, nothing started" >&2
  exit 0
fi

[ "$EUID" -eq 0 ] || die "must run as root (DHCP/PXE need ports 67, 69 and 4011)"

# --- serve --------------------------------------------------------------------
# linkFarm results are symlinks into the store; deref them so the HTTP server
# does not have to follow links out of its root.
ROOT=$(mktemp -d)
mkdir -p "$ROOT/boot" "$ROOT/ghaf-image"
cp -L "$NETBOOT_DIR/bzImage" "$ROOT/boot/bzImage"
cp -L "$NETBOOT_DIR/initrd" "$ROOT/boot/initrd"
ln -s "$(readlink -f "$IMAGE_DIR/ghaf-image.raw.zst")" "$ROOT/ghaf-image/ghaf-image.raw.zst"
ln -s "$(readlink -f "$IMAGE_DIR/ghaf-image.bmap")" "$ROOT/ghaf-image/ghaf-image.bmap"

API_PID=""
PIXIE_PID=""
# Every step here is best-effort and MUST NOT be able to abort the ones after it.
cleanup() {
  [ -n "$API_PID" ] && kill "$API_PID" 2>/dev/null || true
  [ -n "$PIXIE_PID" ] && kill "$PIXIE_PID" 2>/dev/null || true
  firewall_close || true
  rm -rf "$ROOT" || true
  echo "ghaf-netboot: stopped" >&2
}
trap cleanup EXIT INT TERM

$OPEN_FIREWALL && firewall_open

mac_args=()
for m in "${MACS[@]}"; do mac_args+=(--mac "$m"); done

serve_args=()
$EXIT_AFTER_SERVE && serve_args+=(--exit-after-serve)

ghaf-netboot-api --root "$ROOT" --listen "$LISTEN_IP" --port "$PORT" \
  --cmdline "$CMDLINE" "${mac_args[@]}" "${serve_args[@]+"${serve_args[@]}"}" &
API_PID=$!
sleep 1
kill -0 "$API_PID" 2>/dev/null || die "HTTP server failed to start"

# --debug and --log-timestamps are not optional niceties here. Without --debug,
# pixiecore logs nothing at all for a DHCP client it does not end up booting
ipxe_args=()
[ -n "$IPXE_EFI64" ] && ipxe_args+=(--ipxe-efi64 "$IPXE_EFI64")

pixiecore api "http://${LISTEN_IP}:${PORT}" \
  --listen-addr "$LISTEN_IP" \
  --port "$((PORT + 1))" \
  "${ipxe_args[@]+"${ipxe_args[@]}"}" \
  --debug --log-timestamps &
PIXIE_PID=$!

# G6: the realistic failure is not a misconfigured run, it is someone forgetting
# to stop the server and carrying the laptop into a meeting.
if [ "$TIMEOUT_MIN" != 0 ]; then
  (
    sleep $((TIMEOUT_MIN * 60))
    echo "ghaf-netboot: ${TIMEOUT_MIN} minute timeout reached, stopping" >&2
    kill -TERM $$ 2>/dev/null
  ) &
fi

echo "ghaf-netboot: ready. Boot the target from the network." >&2
wait -n "$API_PID" "$PIXIE_PID"
