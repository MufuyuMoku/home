#!/usr/bin/env bash
# Project HOME: backup /mnt/data ke laptop dengan restic (lewat rclone/SFTP).
# Rancangan: docs/rancangan-backup.md. Dijalankan oleh home-backup.service / home-check.service.
#
# Pemakaian (di STB, sebagai root):
#   backup.sh backup   # snapshot + forget (prune hari Minggu) + cek ukuran + push Uptime Kuma
#   backup.sh check    # restic check --read-data-subset=5%
#
# Exit: 0 = sukses ATAU dilewati (kartu data/laptop tidak ada); 1 = gagal; 2 = backup sukses
# tapi repo melebihi batas ukuran.
# Rahasia TIDAK ada di repo: password di /root/.config/restic/password, URL push di
# /root/.config/restic/push-url (keduanya 600, dibuat klien).

set -euo pipefail

MODE="${1:-backup}"
DATA=/mnt/data
DATA_LABEL=HOMEDATA
export RESTIC_REPOSITORY=rclone:laptop-backup:/restic
export RESTIC_PASSWORD_FILE=/root/.config/restic/password
export RESTIC_CACHE_DIR=$DATA/.restic-cache       # di kartu data, bukan eMMC
PUSH_URL_FILE=/root/.config/restic/push-url
RCLONE_REMOTE=laptop-backup:/restic
DB_CONTAINERS=(gitea uptime-kuma filebrowser-quantum)   # di-stop selama snapshot
EXCLUDES=(
  "$DATA/docker"                           # image/container: bisa diunduh ulang
  "$DATA/filebrowser-quantum/data/tmp"     # cache/index FileBrowser Quantum
  "$DATA/lost+found"
  "$DATA/.restic-cache"
)
KEEP=(--keep-daily 7 --keep-weekly 4 --keep-monthly 6)
MAX_REPO_BYTES=$((15 * 1000 * 1000 * 1000))   # 15 GB
STATE_DIR=/var/lib/home-backup
STOPPED_FILE=$STATE_DIR/stopped-containers
LOCK_FILE=/run/home-backup.lock

log()  { echo "[home-backup] $*"; }
fail() { echo "[home-backup] GAGAL: $*" >&2; push down "gagal"; exit 1; }

# Kirim status ke monitor Push Uptime Kuma. URL tidak pernah dicetak.
push() {
  local status=$1 msg=$2 url base
  [ -s "$PUSH_URL_FILE" ] || { log "PERINGATAN: $PUSH_URL_FILE belum ada, status tidak dikirim"; return 0; }
  url=$(head -n1 "$PUSH_URL_FILE"); base=${url%%\?*}
  msg=$(printf '%s' "$msg" | tr -c 'A-Za-z0-9._-' '-')
  # Uptime Kuma ikut di-stop selama snapshot; setelah start ia butuh beberapa puluh detik
  # sebelum siap menerima push. Coba ulang sampai sekitar 2 menit.
  local i
  for i in $(seq 1 12); do
    if curl -fsS -m 15 -o /dev/null "$base?status=$status&msg=$msg&ping=" 2>/dev/null; then
      log "status '$status' terkirim ke Uptime Kuma (percobaan ke-$i)"
      return 0
    fi
    sleep 10
  done
  log "PERINGATAN: gagal mengirim status ke Uptime Kuma"
}

start_stopped() {
  [ -s "$STOPPED_FILE" ] || return 0
  local c
  while read -r c; do
    [ -n "$c" ] || continue
    if docker start "$c" >/dev/null 2>&1; then log "container $c dinyalakan lagi"
    else echo "[home-backup] PERINGATAN: container $c gagal dinyalakan" >&2; fi
  done < "$STOPPED_FILE"
  rm -f "$STOPPED_FILE"
}

# --- Kunci: satu proses backup/check pada satu waktu ---------------------------
mkdir -p "$STATE_DIR"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then log "proses lain sedang berjalan, DILEWATI"; exit 0; fi

# Kalau run sebelumnya terputus (mis. listrik mati) saat container di-stop, nyalakan dulu.
start_stopped

# --- Pemeriksaan awal (dilewati, bukan gagal) ----------------------------------
src=$(findmnt -no SOURCE "$DATA" || true)
if [ -z "$src" ] || [ "$(lsblk -no LABEL "$src" 2>/dev/null)" != "$DATA_LABEL" ]; then
  log "kartu data $DATA ($DATA_LABEL) tidak ter-mount, DILEWATI"; exit 0
fi
if ! rclone lsf --max-depth 1 --contimeout 10s --timeout 30s --retries 1 --low-level-retries 1 \
     "$RCLONE_REMOTE" >/dev/null 2>&1; then
  log "laptop ($RCLONE_REMOTE) tidak terjangkau, DILEWATI"; exit 0
fi
[ -s "$RESTIC_PASSWORD_FILE" ] || fail "$RESTIC_PASSWORD_FILE tidak ada"
mkdir -p "$RESTIC_CACHE_DIR"

case "$MODE" in
  check)
    log "restic check --read-data-subset=5%"
    restic check --read-data-subset=5% || fail "restic check menemukan masalah"
    log "check selesai tanpa masalah"
    exit 0
    ;;
  backup) ;;
  *) echo "Pemakaian: $0 [backup|check]" >&2; exit 2 ;;
esac

# --- Snapshot (container database di-stop sebentar) ----------------------------
trap 'start_stopped' EXIT
trap 'start_stopped; exit 1' INT TERM

: > "$STOPPED_FILE"
for c in "${DB_CONTAINERS[@]}"; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null || echo false)" = true ]; then
    echo "$c" >> "$STOPPED_FILE"          # dicatat SEBELUM di-stop
    docker stop -t 30 "$c" >/dev/null
    log "container $c di-stop"
  fi
done

exclude_args=()
for e in "${EXCLUDES[@]}"; do exclude_args+=(--exclude "$e"); done
log "restic backup $DATA"
backup_ok=1
restic backup --host aml-s9xx-box --tag home "${exclude_args[@]}" "$DATA" || backup_ok=0

start_stopped                               # layanan kembali secepatnya
[ "$backup_ok" -eq 1 ] || fail "restic backup gagal"

# --- Retensi --------------------------------------------------------------------
if [ "$(date +%u)" = 7 ]; then
  log "forget + prune (hari Minggu)"
  restic forget --host aml-s9xx-box --tag home "${KEEP[@]}" --prune || fail "restic forget/prune gagal"
else
  restic forget --host aml-s9xx-box --tag home "${KEEP[@]}" || fail "restic forget gagal"
fi

# --- Batas ukuran repo -------------------------------------------------------------
repo_bytes=$(rclone size --json "$RCLONE_REMOTE" 2>/dev/null | jq -r '.bytes // empty' || true)
[[ "$repo_bytes" =~ ^[0-9]+$ ]] || fail "ukuran repo tidak bisa dibaca"
repo_gb=$(awk -v b="$repo_bytes" 'BEGIN { printf "%.2f", b / 1e9 }')
repo_mb=$(awk -v b="$repo_bytes" 'BEGIN { printf "%.1f", b / 1e6 }')
log "ukuran repo: ${repo_mb} MB (batas 15 GB)"
if [ "$repo_bytes" -gt "$MAX_REPO_BYTES" ]; then
  echo "[home-backup] PERINGATAN: repo ${repo_gb} GB melebihi batas 15 GB" >&2
  push down "repo-${repo_gb}GB-melebihi-15GB"
  exit 2
fi

push up "OK-${repo_mb}MB"
log "backup selesai"
