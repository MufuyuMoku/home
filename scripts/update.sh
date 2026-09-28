#!/usr/bin/env bash
# Project HOME: update paket manual yang aman.
#
# Pemakaian (di STB, sebagai root):
#   scripts/update.sh --dry-run   # hanya cek + simulasi; tidak meng-upgrade apa pun
#   screen -S update scripts/update.sh
#                                 # upgrade sungguhan, WAJIB di dalam screen/tmux
#
# Script berhenti (exit != 0) kalau ada kondisi yang tidak sesuai:
# hold hilang, repo beta aktif, initramfs tidak beku, paket dari repo selain
# Ubuntu/Docker, paket Armbian/kernel/bootloader, atau paket yang memiliki file di /boot.
# Catatan: --dry-run tetap menjalankan `apt-get update` (hanya menyegarkan daftar paket).

set -euo pipefail

DRY_RUN=0
case "${1:-}" in
  --dry-run) DRY_RUN=1 ;;
  "") ;;
  *) echo "Pemakaian: $0 [--dry-run]" >&2; exit 2 ;;
esac

REQUIRED_HOLDS=(
  linux-image-current-meson64
  linux-dtb-current-meson64
  armbian-bsp-cli-aml-s9xx-box-current
  armbian-config
  armbian-firmware
  armbian-plymouth-theme
  armbian-zsh
  base-files
)
ALLOWED_SOURCES_RE='^https?://(ports\.ubuntu\.com|download\.docker\.com)(/|$)'
FORBIDDEN_PKG_RE='^(armbian-|linux-image-|linux-dtb-|linux-u-boot-|u-boot-)'
CHECK_SERVICES=(ssh NetworkManager docker)
STATE_DIR=/root/home-update
TS=$(date +%Y%m%d-%H%M%S)

log()  { echo "[update] $*"; }
fail() { echo "[update] BERHENTI: $*" >&2; exit 1; }

boot_md5() { find /boot -type f -exec md5sum {} + | sort -k2; }

# --- 1. Pemeriksaan awal -----------------------------------------------------
[ "$(id -u)" -eq 0 ] || fail "harus dijalankan sebagai root"

holds=$(apt-mark showhold)
for p in "${REQUIRED_HOLDS[@]}"; do
  grep -qx "$p" <<<"$holds" || fail "paket $p tidak di-hold"
done
log "hold OK (${#REQUIRED_HOLDS[@]} paket wajib)"

if grep -rEq '^[[:space:]]*[^#].*beta\.armbian\.com' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
  fail "repo beta.armbian.com aktif"
fi
log "repo beta nonaktif OK"

grep -qx 'update_initramfs=no' /etc/initramfs-tools/update-initramfs.conf \
  || fail "update_initramfs bukan 'no' (initramfs tidak beku)"
log "initramfs beku OK"

if [ "$DRY_RUN" -eq 0 ] && [ -z "${STY:-}" ] && [ -z "${TMUX:-}" ]; then
  fail "upgrade sungguhan harus dijalankan di dalam screen atau tmux"
fi

ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1 || fail "STB tidak terhubung ke internet"
log "internet OK"

# --- 2. Segarkan daftar paket & simulasi --------------------------------------
log "apt-get update"
apt-get update -qq || fail "apt-get update gagal"

sim=$(apt-get -s upgrade)
mapfile -t pkgs < <(awk '/^Inst /{print $2}' <<<"$sim")

if grep -q '^Remv ' <<<"$sim"; then
  fail "simulasi akan menghapus paket: $(awk '/^Remv /{print $2}' <<<"$sim" | tr '\n' ' ')"
fi

if [ "${#pkgs[@]}" -eq 0 ]; then
  log "tidak ada paket yang perlu di-upgrade"
  [ "$DRY_RUN" -eq 1 ] || { apt-get clean; log "apt-get clean selesai"; }
  exit 0
fi
log "${#pkgs[@]} paket akan di-upgrade"

bad=()
for p in "${pkgs[@]}"; do
  if [[ "$p" =~ $FORBIDDEN_PKG_RE ]]; then
    bad+=("$p (paket Armbian/kernel/bootloader)"); continue
  fi
  cand=$(apt-cache policy "$p" | awk '/Candidate:/{print $2}')
  src=$(apt-cache policy "$p" | grep -A1 -F " $cand " | grep -oE 'https?://[^ ]+' | head -1 || true)
  if ! [[ "$src" =~ $ALLOWED_SOURCES_RE ]]; then
    bad+=("$p $cand dari '${src:-tidak diketahui}'"); continue
  fi
  if dpkg -L "$p" 2>/dev/null | grep -q '^/boot'; then
    bad+=("$p (memiliki file di /boot)")
  fi
done
if [ "${#bad[@]}" -gt 0 ]; then
  printf '[update]   - %s\n' "${bad[@]}" >&2
  fail "ada paket yang tidak diizinkan (lihat daftar di atas)"
fi
log "semua paket berasal dari Ubuntu/Docker dan tidak menyentuh /boot"

if [ "$DRY_RUN" -eq 1 ]; then
  log "--dry-run: daftar paket yang akan di-upgrade:"
  printf '  %s\n' "${pkgs[@]}"
  log "--dry-run selesai, tidak ada yang diubah"
  exit 0
fi

# --- 3. Upgrade sungguhan ----------------------------------------------------
mkdir -p "$STATE_DIR"
boot_md5 > "$STATE_DIR/boot-md5-$TS-before.txt"
log "potret /boot: $STATE_DIR/boot-md5-$TS-before.txt"

if ! DEBIAN_FRONTEND=noninteractive apt-get -y \
     -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
     upgrade 2>&1 | tee "$STATE_DIR/upgrade-$TS.log"; then
  fail "apt-get upgrade gagal (log: $STATE_DIR/upgrade-$TS.log)"
fi

apt-get clean
log "apt-get clean selesai"

# --- 4. Verifikasi -----------------------------------------------------------
boot_md5 > "$STATE_DIR/boot-md5-$TS-after.txt"
if ! diff -q "$STATE_DIR/boot-md5-$TS-before.txt" "$STATE_DIR/boot-md5-$TS-after.txt" >/dev/null; then
  diff "$STATE_DIR/boot-md5-$TS-before.txt" "$STATE_DIR/boot-md5-$TS-after.txt" >&2 || true
  fail "/boot BERUBAH setelah upgrade. Jangan reboot, laporkan ke klien"
fi
log "/boot identik"

holds=$(apt-mark showhold)
for p in "${REQUIRED_HOLDS[@]}"; do
  grep -qx "$p" <<<"$holds" || fail "hold $p hilang setelah upgrade"
done
log "hold tetap OK"

for s in "${CHECK_SERVICES[@]}"; do
  systemctl is-active --quiet "$s" || fail "layanan $s tidak aktif"
done
log "layanan ${CHECK_SERVICES[*]} aktif"

if [ -e /var/run/reboot-required ]; then
  log "PERHATIAN: sistem meminta reboot. Minta izin klien dulu."
fi
log "selesai"
