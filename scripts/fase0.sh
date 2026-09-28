#!/usr/bin/env bash
# Project HOME: Fase 0 (fondasi), bisa dijalankan ulang (idempoten).
#
# Merangkum yang sudah dikerjakan manual pada 2026-09-28 (lihat docs/log.md):
#   1. inventaris
#   2. hold paket, repo beta mati, initramfs beku, auto-update mati,
#      upgrade lewat scripts/update.sh
#   3. zona waktu Asia/Jakarta
#   4. devmon mati; kartu data (microSD via card reader USB) di /mnt/data
#      -> FORMAT & FSTAB TETAP MANUAL (butuh konfirmasi klien); script hanya memeriksa
#   5. Docker: daemon.json (data-root /mnt/data/docker, overlay2, log 10m x 3)
#      + drop-in RequiresMountsFor=/mnt/data
#
# Pemakaian (di STB, sebagai root, repo disalin ke /opt/home):
#   screen -S fase0 /opt/home/scripts/fase0.sh
#
# Script berhenti kalau ada kondisi yang tidak sesuai. Tidak ada yang menyentuh
# kernel, DTB, bootloader, /boot, jaringan, SSH, slot SD (mmcblk1), atau memformat
# disk apa pun. Tidak ada reboot.

set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
BACKUP_DIR=/root/fase0/backup
TZ_TARGET=Asia/Jakarta

MANDATORY_HOLDS=(linux-image-current-meson64 linux-dtb-current-meson64 armbian-bsp-cli-aml-s9xx-box-current)
EXTRA_HOLDS=(armbian-config armbian-firmware armbian-plymouth-theme armbian-zsh base-files)

ARMBIAN_SOURCES=/etc/apt/sources.list.d/armbian.sources
INITRAMFS_CONF=/etc/initramfs-tools/update-initramfs.conf
NO_AUTO_UPGRADES=/etc/apt/apt.conf.d/99home-no-auto-upgrades
DAEMON_JSON_SRC="$REPO_DIR/config/etc/docker/daemon.json"
DAEMON_JSON=/etc/docker/daemon.json
DROPIN_SRC="$REPO_DIR/config/etc/systemd/system/docker.service.d/10-home-requires-data.conf"
DROPIN=/etc/systemd/system/docker.service.d/10-home-requires-data.conf
DATA_MNT=/mnt/data
DATA_LABEL=HOMEDATA

log()  { echo "[fase0] $*"; }
step() { echo; echo "[fase0] === $* ==="; }
fail() { echo "[fase0] BERHENTI: $*" >&2; exit 1; }

# Backup sekali saja: backup pertama adalah file asli, jangan ditimpa.
backup_once() {
  mkdir -p "$BACKUP_DIR"
  local dst="$BACKUP_DIR/$(basename "$1")"
  if [ -e "$1" ] && [ ! -e "$dst" ]; then cp -a "$1" "$dst"; log "backup: $1 -> $dst"; fi
}

installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }

# --- Pemeriksaan awal ------------------------------------------------------
[ "$(id -u)" -eq 0 ] || fail "harus dijalankan sebagai root"
[ "$(uname -m)" = aarch64 ] || fail "bukan arm64 ($(uname -m))"
[ -n "${STY:-}${TMUX:-}" ] || fail "jalankan di dalam screen atau tmux (ada apt upgrade)"
[ "$(findmnt -no LABEL /)" = ROOT_EMMC ] || fail "root filesystem bukan ROOT_EMMC; ini bukan STB yang diharapkan"
[ -x "$REPO_DIR/scripts/update.sh" ] || fail "scripts/update.sh tidak ditemukan / tidak executable"
[ -f "$DAEMON_JSON_SRC" ] || fail "$DAEMON_JSON_SRC tidak ditemukan"
[ -f "$DROPIN_SRC" ] || fail "$DROPIN_SRC tidak ditemukan"

# --- 1. Inventaris (hanya membaca) -----------------------------------------
step "1. Inventaris"
mkdir -p /root/fase0
INV=/root/fase0/inventaris-$(date +%Y%m%d-%H%M%S).txt
{
  for c in "uname -a" "cat /etc/os-release" "lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT" \
           "df -h" "free -h" "apt-mark showhold" "zramctl"; do
    echo "### $c"; eval "$c"; echo
  done
} > "$INV" 2>&1
log "tersimpan di $INV"

# --- 2a. Hold paket --------------------------------------------------------
step "2a. Hold paket"
for p in "${MANDATORY_HOLDS[@]}"; do
  installed "$p" || fail "paket wajib $p tidak terpasang; periksa manual"
  apt-mark hold "$p" >/dev/null
done
for p in "${EXTRA_HOLDS[@]}"; do
  if installed "$p"; then apt-mark hold "$p" >/dev/null; else log "lewati $p (tidak terpasang)"; fi
done
apt-mark showhold | sed 's/^/  hold: /'

# --- 2b. Repo Armbian beta nonaktif ----------------------------------------
step "2b. Repo Armbian beta"
if [ -f "$ARMBIAN_SOURCES" ] && grep -Eq '^[[:space:]]*[^#[:space:]]' "$ARMBIAN_SOURCES"; then
  grep -q 'beta\.armbian\.com' "$ARMBIAN_SOURCES" \
    || fail "$ARMBIAN_SOURCES aktif tapi bukan repo beta; periksa manual"
  backup_once "$ARMBIAN_SOURCES"
  sed -i 's/^\([^#]\)/# \1/' "$ARMBIAN_SOURCES"
  sed -i "1i # Dinonaktifkan $(date +%F) (Project HOME): repo beta/nightly tidak dipakai. Jangan aktifkan tanpa persetujuan klien." "$ARMBIAN_SOURCES"
  log "repo beta dinonaktifkan"
else
  log "sudah nonaktif"
fi
if grep -rEq '^[[:space:]]*[^#].*beta\.armbian\.com' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
  fail "masih ada sumber beta.armbian.com aktif di file lain"
fi

# --- 2c. Initramfs beku ----------------------------------------------------
step "2c. Initramfs beku"
if grep -qx 'update_initramfs=no' "$INITRAMFS_CONF"; then
  log "sudah beku"
elif grep -qx 'update_initramfs=yes' "$INITRAMFS_CONF"; then
  backup_once "$INITRAMFS_CONF"
  sed -i 's/^update_initramfs=yes$/update_initramfs=no/' "$INITRAMFS_CONF"
  log "update_initramfs=no"
else
  fail "baris update_initramfs tidak dikenali di $INITRAMFS_CONF"
fi

# --- 2d. Update otomatis mati ----------------------------------------------
step "2d. Update otomatis"
want='// Project HOME: update otomatis dimatikan. Update manual lewat scripts/update.sh.
// Untuk mengaktifkan kembali: hapus file ini.
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";'
if [ "$(cat "$NO_AUTO_UPGRADES" 2>/dev/null)" != "$want" ]; then
  printf '%s\n' "$want" > "$NO_AUTO_UPGRADES"
  log "ditulis: $NO_AUTO_UPGRADES"
else
  log "sudah mati"
fi
apt-config dump | grep -Eq '^APT::Periodic::Unattended-Upgrade "0";' || fail "Unattended-Upgrade belum 0"

# --- 2e. Upgrade paket (lewat update.sh, termasuk apt-get clean) -----------
step "2e. Upgrade paket"
"$REPO_DIR/scripts/update.sh"

# --- 3. Zona waktu ---------------------------------------------------------
step "3. Zona waktu"
if [ "$(timedatectl show -p Timezone --value)" != "$TZ_TARGET" ]; then
  timedatectl set-timezone "$TZ_TARGET"
  log "diubah ke $TZ_TARGET"
else
  log "sudah $TZ_TARGET"
fi

# --- 4. Kartu data ---------------------------------------------------------
step "4. Kartu data"
if systemctl list-unit-files 'devmon@.service' --no-legend | grep -q devmon; then
  if systemctl is-enabled --quiet devmon@devmon.service 2>/dev/null \
     || systemctl is-active --quiet devmon@devmon.service; then
    systemctl disable --now devmon@devmon.service
    log "devmon dimatikan"
  else
    log "devmon sudah mati"
  fi
fi
if findmnt -rn | grep -q ' /media/devmon'; then
  fail "masih ada mount di /media/devmon; lepas manual dulu"
fi
# Slot SD STB tidak dipakai (aturan 11): tidak boleh ada mount dari mmcblk1.
if findmnt -rno SOURCE | grep -q '^/dev/mmcblk1'; then
  fail "ada partisi slot SD (mmcblk1) yang ter-mount; slot SD tidak boleh dipakai"
fi
# Format + fstab kartu data SENGAJA manual (butuh konfirmasi klien atas device-nya):
#   lsblk -o NAME,SIZE,TYPE,TRAN,MODEL,MOUNTPOINT   -> /dev/sdX, TRAN=usb, 100-130 GB
#   wipefs -a /dev/sdX1 /dev/sdX; printf 'label: gpt\n,,L\n' | sfdisk /dev/sdX
#   mkfs.ext4 -L HOMEDATA -m 1 /dev/sdX1; mkdir -p /mnt/data
#   fstab: UUID=<uuid> /mnt/data ext4 defaults,noatime,nofail,x-systemd.device-timeout=10s 0 2
#   findmnt --verify && mount -a
# Di sini hanya diperiksa bahwa langkah manual itu sudah beres.
fstab_line=$(awk -v m="$DATA_MNT" '$1 !~ /^#/ && $2 == m' /etc/fstab)
[ -n "$fstab_line" ] || fail "belum ada entri fstab untuk $DATA_MNT (siapkan kartu data manual dulu, lihat komentar di atas)"
[[ "$fstab_line" == UUID=* ]] || fail "entri fstab $DATA_MNT tidak memakai UUID"
[[ "$fstab_line" == *nofail* ]] || fail "entri fstab $DATA_MNT tidak memakai nofail"
findmnt --verify >/dev/null 2>&1 || fail "findmnt --verify melaporkan error"
data_src=$(findmnt -no SOURCE "$DATA_MNT" || true)
[ -n "$data_src" ] || fail "$DATA_MNT tidak ter-mount"
[ "$(lsblk -no LABEL "$data_src")" = "$DATA_LABEL" ] || fail "$DATA_MNT bukan filesystem berlabel $DATA_LABEL"
[ "$(lsblk -dno TRAN "/dev/$(lsblk -no PKNAME "$data_src")")" = usb ] || fail "$DATA_MNT bukan disk USB"
log "$DATA_MNT OK ($data_src, $DATA_LABEL, usb)"

# --- 5. Docker -------------------------------------------------------------
step "5. Docker"
# TODO: di STB proyek ini Docker sudah terpasang dari download.docker.com sebelum
# proyek dimulai. Pemasangan otomatis untuk STB baru belum dibuat/diuji.
command -v docker >/dev/null || fail "Docker belum terpasang (pemasangan belum diotomatiskan)"
docker compose version >/dev/null 2>&1 || fail "docker compose plugin belum terpasang"

changed=0
if ! cmp -s "$DROPIN_SRC" "$DROPIN"; then
  mkdir -p "$(dirname "$DROPIN")"
  install -m 644 -o root -g root "$DROPIN_SRC" "$DROPIN"
  systemctl daemon-reload
  changed=1
  log "drop-in RequiresMountsFor=$DATA_MNT dipasang"
fi
if ! cmp -s "$DAEMON_JSON_SRC" "$DAEMON_JSON"; then
  dockerd --validate --config-file "$DAEMON_JSON_SRC" >/dev/null || fail "daemon.json di repo tidak valid"
  # Ganti data-root/storage driver hanya kalau Docker masih kosong (tidak ada data yang tertinggal).
  if [ "$(docker info --format '{{.DockerRootDir}}')" != "$DATA_MNT/docker" ]; then
    [ -z "$(docker ps -aq)" ] && [ -z "$(docker images -aq)" ] \
      || fail "Docker sudah punya container/image di data-root lama; pindahkan manual"
  fi
  mkdir -p /etc/docker "$DATA_MNT/docker"
  chmod 710 "$DATA_MNT/docker"
  backup_once "$DAEMON_JSON"
  install -m 644 -o root -g root "$DAEMON_JSON_SRC" "$DAEMON_JSON"
  changed=1
  log "daemon.json dipasang"
fi
if [ "$changed" -eq 1 ]; then systemctl restart docker; log "docker di-restart"; else log "konfigurasi Docker sudah sesuai"; fi
systemctl is-active --quiet docker || fail "docker tidak aktif"
[ "$(docker info --format '{{.DockerRootDir}}')" = "$DATA_MNT/docker" ] || fail "Docker Root Dir bukan $DATA_MNT/docker"
[ "$(docker info --format '{{.Driver}}')" = overlay2 ] || fail "storage driver bukan overlay2"
systemctl show docker -p RequiresMountsFor --value | grep -qw "$DATA_MNT" || fail "docker.service tidak RequiresMountsFor=$DATA_MNT"
log "Docker: root $DATA_MNT/docker, overlay2, menunggu $DATA_MNT"

had_hello=0
docker image inspect hello-world >/dev/null 2>&1 && had_hello=1
docker run --rm hello-world >/dev/null || fail "docker run hello-world gagal"
[ "$had_hello" -eq 1 ] || docker rmi hello-world >/dev/null
log "docker run hello-world OK"

step "Selesai"
log "RAM: $(free -h | awk '/^Mem:/{print $7" tersedia dari "$2}')"
log "eMMC /: $(df -h / | awk 'NR==2{print $5" terpakai, sisa "$4}')"
