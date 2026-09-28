# Project HOME: pengaturan restic untuk pemakaian manual (restore, melihat snapshot).
# Pemakaian di STB:  source /opt/home/scripts/restic-env.sh   lalu  restic snapshots
# Sama dengan yang dipakai scripts/backup.sh. Tidak berisi rahasia.
export RESTIC_REPOSITORY=rclone:laptop-backup:/restic
export RESTIC_PASSWORD_FILE=/root/.config/restic/password
export RESTIC_CACHE_DIR=/mnt/data/.restic-cache
