# Memulihkan data dari backup: Project HOME

Backup berisi seluruh `/mnt/data` (kartu data), **kecuali** `docker/` (image bisa diunduh ulang),
cache FileBrowser Quantum (`filebrowser-quantum/data/tmp/`), `lost+found/`, dan cache restic.
Backup disimpan terenkripsi di laptop: `C:\HOME-backup\restic`. Rancangannya ada di [rancangan-backup.md](rancangan-backup.md).

Yang kamu butuhkan:
- **Password repo restic** dari password manager. Tanpa password ini backup tidak bisa dibuka.
- Laptop menyala dan tersambung kabel ke STB (backup dibaca dari laptop lewat SFTP).

> Semua perintah di bawah dijalankan di STB sebagai root: dari terminal laptop ketik `ssh stb`.
> Baris yang diawali `#` hanya penjelasan, tidak perlu diketik.

---

## 0. Persiapan (selalu)

```bash
source /opt/home/scripts/restic-env.sh
# Hentikan backup terjadwal selama memulihkan, supaya tidak berjalan bersamaan:
systemctl stop home-backup.timer home-check.timer
# Lihat daftar snapshot (paling baru di bawah):
restic snapshots
```

Kolom **ID** (misalnya `71c9ad72`) dipakai untuk memilih snapshot. `latest` artinya snapshot terbaru.

Untuk melihat isi satu snapshot tanpa memulihkan apa pun:

```bash
restic ls latest /mnt/data/files
```

**Jangan lupa** menyalakan lagi backup terjadwal setelah selesai (langkah terakhir setiap bagian).

---

## 1. Memulihkan satu file (misalnya terhapus tidak sengaja)

Contoh: `/mnt/data/files/laporan.pdf` terhapus.

```bash
# 1. Cari snapshot yang masih berisi file itu:
restic find /mnt/data/files/laporan.pdf
# 2. Pulihkan ke folder sementara dulu (tidak menimpa apa pun):
restic restore latest --target /tmp/pulih --include /mnt/data/files/laporan.pdf
# 3. Periksa hasilnya, lalu salin kembali ke tempatnya (pemilik & izin ikut terbawa):
ls -la /tmp/pulih/mnt/data/files/
cp -a /tmp/pulih/mnt/data/files/laporan.pdf /mnt/data/files/
# 4. Bersihkan dan nyalakan lagi backup terjadwal:
rm -rf /tmp/pulih
systemctl start home-backup.timer home-check.timer
```

Ganti `latest` dengan ID snapshot kalau yang dibutuhkan versi lebih lama.
Untuk satu folder, pakai jalur folder di `--include` dan `cp -a` foldernya.

---

## 2. Memulihkan satu layanan (misalnya database Gitea rusak)

Contoh untuk **Gitea**. Untuk layanan lain, ganti `gitea` dengan nama layanannya:

| Layanan | Folder service | Folder data |
|---|---|---|
| Gitea | `/opt/home/services/gitea` | `/mnt/data/gitea` |
| Uptime Kuma | `/opt/home/services/uptime-kuma` | `/mnt/data/uptime-kuma` |
| FileBrowser Quantum | `/opt/home/services/filebrowser-quantum` | `/mnt/data/filebrowser-quantum` |
| Homepage | `/opt/home/services/homepage` | `/mnt/data/homepage` |

```bash
# 1. Hentikan layanannya:
cd /opt/home/services/gitea && docker compose stop
# 2. Pulihkan ke folder sementara di kartu data (bukan /tmp: /tmp ada di RAM):
restic restore latest --target /mnt/data/pulih-tmp --include /mnt/data/gitea
# 3. Simpan data lama dengan nama lain (JANGAN dihapus dulu), lalu pasang hasil pulihan:
mv /mnt/data/gitea /mnt/data/gitea.rusak-$(date +%Y%m%d)
mv /mnt/data/pulih-tmp/mnt/data/gitea /mnt/data/gitea
rm -rf /mnt/data/pulih-tmp
# 4. Nyalakan lagi dan tes dari browser (http://192.168.137.202:3002):
docker compose up -d
# 5. Nyalakan lagi backup terjadwal:
systemctl start home-backup.timer home-check.timer
```

Kalau layanan sudah dipastikan normal, folder `gitea.rusak-…` boleh dihapus.

---

## 3. Memulihkan seluruh kartu data ke kartu baru (kartu rusak/hilang)

**3a. STB masih normal (hanya kartu yang diganti).** Minta Claude Code mengerjakan bagian format,
karena format butuh konfirmasi device (aturan 5 di CLAUDE.md):

1. Colok kartu baru lewat card reader USB. Format sesuai **README "Membangun ulang dari nol" langkah 3**
   (GPT, `mkfs.ext4 -L HOMEDATA -m 1`). **UUID kartu baru berbeda**, jadi baris `/mnt/data` di
   `/etc/fstab` harus diganti UUID-nya (backup fstab dulu, lalu `findmnt --verify` dan `mount -a`).
2. Pulihkan semuanya:
   ```bash
   systemctl stop docker.socket docker
   source /opt/home/scripts/restic-env.sh
   export RESTIC_CACHE_DIR=/tmp/restic-cache   # cache lama ikut hilang bersama kartu
   restic restore latest --target /
   mkdir -p /mnt/data/docker && chmod 710 /mnt/data/docker
   systemctl start docker
   ```
3. Nyalakan setiap layanan (image diunduh ulang, butuh internet):
   ```bash
   for s in filebrowser-quantum gitea uptime-kuma homepage; do (cd /opt/home/services/$s && docker compose up -d); done
   ```
4. Tes semua layanan dari browser, lalu `systemctl start home-backup.timer home-check.timer`.

**3b. STB juga harus dibangun ulang (eMMC di-flash ulang).** Ikuti README "Membangun ulang dari nol"
sampai kartu data siap, lalu siapkan backup lagi (bagian B di [rancangan-backup.md](rancangan-backup.md)):
pasang `restic` dan `rclone` dari apt, buat key backup baru, jalankan lagi
`scripts/laptop/setup-backup-target.ps1` di laptop dengan **public key yang baru**, pasang
`rclone.conf` dari `config/root/.config/rclone/rclone.conf.example`, cocokkan sidik jari host key laptop
dan tambahkan ke `known_hosts`, lalu masukkan **password yang sama** dari password manager
(**jangan** `restic init`, karena repo sudah ada). Setelah itu lakukan langkah 3a nomor 2–4.
URL push Uptime Kuma perlu disimpan ulang ke `/root/.config/restic/push-url`.

**3c. Darurat: STB tidak ada sama sekali.** Backup bisa dibuka langsung di laptop dengan
`restic.exe` untuk Windows (github.com/restic/restic/releases). Di PowerShell:
`restic.exe -r C:\HOME-backup\restic restore latest --target C:\pulih`. Isinya berupa file biasa
(repo Gitea, database, dan file-filemu) di `C:\pulih\mnt\data\`.

---

## Yang TIDAK ada di backup

| Hal | Cara mendapatkannya lagi |
|---|---|
| Sistem STB (eMMC) | Dibangun ulang dari repo ini (README) |
| Image Docker | Diunduh ulang otomatis saat `docker compose up -d` |
| Password repo restic | Password manager klien |
| Key backup SSH STB, URL push | Dibuat/disimpan ulang (bagian 3b) |
| Kode proyek | GitHub `MufuyuMoku/home` (+ mirror di Gitea) |
