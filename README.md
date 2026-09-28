# Project HOME: High Operative Management Environment

> **Status:** Fase 0 (fondasi) dan Fase 1 (starter kit, 4 layanan) selesai dan lulus uji reboot (2026-09-28).
> Backup harian ke laptop aktif dan lulus uji pemulihan (2026-09-29).
> Belum ada: persistent journal, firewall, dan akses jarak jauh (dirancang terpisah oleh konsultan).

Homelab pribadi di sebuah STB bekas. Repo ini adalah **sumber kebenaran**: semua yang terpasang di STB
harus bisa dibangun ulang dari isi repo ini. Semua layanan hanya untuk jaringan lokal, tidak ada yang
diekspos ke internet.

- Aturan kerja dan batasan mutlak: [CLAUDE.md](CLAUDE.md)
- Hasil inventaris hardware: [docs/hardware.md](docs/hardware.md)
- Catatan setiap perubahan (tanggal, apa, kenapa): [docs/log.md](docs/log.md)

## Perangkat

| Hal | Nilai |
|---|---|
| STB | Fiberhome HG680P (Amlogic S905X, 4× Cortex-A53, arm64), RAM ~1,9 GB |
| OS | Armbian 25.8 (Ubuntu 24.04 noble), kernel `6.12.35-current-meson64` (dibekukan) |
| Sistem | eMMC 7,3 GB (`/boot` + `/`) |
| Data | microSD 128 GB lewat card reader USB, ext4 label `HOMEDATA` di `/mnt/data`. Slot SD STB tidak dipakai. |
| Jaringan | LAN langsung ke laptop Windows (ICS). STB `192.168.137.202`, laptop `192.168.137.1` |

STB ini **tidak punya HDMI dan tidak ada router**. Kalau boot atau SSH rusak, satu-satunya jalan adalah
flashing ulang. Karena itu kernel, DTB, bootloader, dan `/boot` tidak pernah disentuh, dan setiap
perubahan SSH/jaringan wajib memakai timer rollback otomatis (lihat CLAUDE.md, aturan 12).

## Layanan

| Layanan | Fungsi | Alamat | Image (di-pin, arm64) | mem_limit |
|---|---|---|---|---|
| Homepage | Dashboard: link ke semua layanan + CPU/RAM/suhu | http://192.168.137.202:3000 | `ghcr.io/gethomepage/homepage:v2.4.0` | 256m |
| Uptime Kuma | Monitoring hidup/matinya layanan | http://192.168.137.202:3001 | `louislam/uptime-kuma:2.5.5-slim` | 384m |
| Gitea (SQLite) | Server Git pribadi, mirror repo GitHub | http://192.168.137.202:3002, git SSH port 2222 | `gitea/gitea:1.27.3` | 384m |
| FileBrowser Quantum | File manager web untuk `/mnt/data/files` | http://192.168.137.202:8080 | `ghcr.io/gtsteffaniak/filebrowser:1.5.6-stable-slim` | 192m |

Semua layanan memakai `restart: unless-stopped` dan menyala otomatis setelah reboot. Docker baru mulai
setelah kartu data terpasang. Pemakaian RAM setelah boot sekitar 650 MB untuk keempat container, dengan
sekitar 1,2 GB masih tersedia. Uptime Kuma memantau Homepage, Gitea, FileBrowser Quantum, dan port SSH Gitea.

Filebrowser upstream **tidak dipakai** (proyeknya diarsipkan 2026-09-01, tanpa patch keamanan).

## Keamanan

- Port yang terbuka ke jaringan hanya 22 (SSH STB), 2222 (git SSH Gitea), 3000, 3001, 3002, 8080. Tidak ada port yang diekspos ke internet.
- SSH STB **hanya dengan key** (`config/etc/ssh/sshd_config.d/10-home.conf`). Login password ditolak.
- CasaOS, rclone, Samba, rpcbind, dan openvpn dimatikan (tidak di-uninstall; cara menyalakan lagi ada di `docs/log.md`).
- Tidak ada container yang mendapat akses `docker.sock`. FileBrowser Quantum hanya melihat `/mnt/data/files`.
- Semua akun admin dibuat klien lewat browser. **Tidak ada password di repo.** File `.env` hanya ada di STB (chmod 600).
- Firewall belum dipasang (ditunda sampai rancangan akses jarak jauh).

## Struktur repo

```
README.md                         # file ini
CLAUDE.md                         # aturan & rancangan (brief konsultan)
docs/hardware.md                  # inventaris hardware
docs/log.md                       # catatan perubahan
config/etc/docker/daemon.json     # data-root /mnt/data/docker, overlay2, rotasi log
config/etc/systemd/system/docker.service.d/10-home-requires-data.conf
config/etc/ssh/sshd_config.d/10-home.conf
scripts/fase0.sh                  # fondasi (idempoten)
scripts/update.sh                 # update paket manual yang aman (--dry-run untuk simulasi)
scripts/backup.sh                 # backup restic (dipanggil home-backup/home-check timer)
scripts/restic-env.sh             # pengaturan restic untuk restore manual (source)
scripts/laptop/*.ps1              # pengaturan laptop sebagai target backup (dijalankan klien)
config/etc/systemd/system/home-*  # unit backup + timer
config/root/.config/rclone/rclone.conf.example
docs/rancangan-backup.md          # rancangan backup (konsultan)
docs/restore.md                   # panduan memulihkan data
services/<nama>/                  # compose.yaml, .env.example, config layanan
```

## Membangun ulang dari nol

1. **Flash** Armbian untuk `aml-s9xx-box` ke eMMC, lalu pasang kunci SSH laptop di `/root/.ssh/authorized_keys`.
   Pastikan `ssh stb` dari laptop berhasil (host `stb` → `192.168.137.202`, user root).
2. **Salin repo** ke STB:
   ```bash
   scp -r config scripts services stb:/opt/home/
   ```
3. **Kartu data (manual, dengan konfirmasi device dari klien).** Colok microSD lewat card reader USB,
   identifikasi dengan `lsblk -o NAME,SIZE,TYPE,TRAN,MODEL,MOUNTPOINT` (`/dev/sdX`, TRAN `usb`, 100–130 GB),
   buat GPT dengan 1 partisi, `mkfs.ext4 -L HOMEDATA -m 1`, lalu tambah entri fstab
   `UUID=<uuid> /mnt/data ext4 defaults,noatime,nofail,x-systemd.device-timeout=10s 0 2`,
   `mkdir /mnt/data`, `findmnt --verify`, dan `mount -a`. Langkah lengkapnya ada di komentar `scripts/fase0.sh`.
4. **Fondasi.** Jalankan di dalam `screen`, karena ada `apt upgrade` di dalamnya:
   ```bash
   ssh stb "screen -S fase0 /opt/home/scripts/fase0.sh"
   ```
   Script ini:
   - menahan paket kernel/Armbian, mematikan repo Armbian beta, membekukan initramfs, dan mematikan update otomatis,
   - meng-upgrade paket dengan aman dan mengatur zona waktu Asia/Jakarta,
   - memeriksa kartu data,
   - memasang Docker dari repo resmi kalau belum ada, dengan data-root `/mnt/data/docker` + overlay2,
   - mematikan layanan yang tidak dipakai,
   - menerapkan SSH hanya-key. **Setelah script selesai, uji koneksi SSH baru dari laptop sebelum menutup sesi.**
5. **Layanan** (satu per satu, tes di browser sebelum lanjut). Untuk setiap layanan: `cd /opt/home/services/<nama>`,
   `cp .env.example .env && chmod 600 .env`, sesuaikan isinya, siapkan folder data, lalu `docker compose up -d`.

   | Layanan | Siapkan dulu | Pertama kali di browser |
   |---|---|---|
   | filebrowser-quantum | `mkdir -p /mnt/data/files /mnt/data/filebrowser-quantum/data`, salin `config.yaml` ke `.../data/`, `chown -R 1000:1000` keduanya | Login `admin`/`admin` (bawaan image), **ganti password segera** |
   | gitea | `mkdir -p /mnt/data/gitea` | Halaman instalasi: biarkan nilai bawaan, **isi "Administrator Account Settings"** (pendaftaran publik dimatikan) |
   | uptime-kuma | `mkdir -p /mnt/data/uptime-kuma` | Pilih **SQLite**, buat akun admin, lalu tambah monitor HTTP untuk `:3000`, `:3002`, `:8080` dan TCP `:2222` (pakai IP, bukan `localhost`) |
   | homepage | `mkdir -p /mnt/data/homepage/config`, salin `config/*.yaml` ke sana, `chown -R 1000:1000 /mnt/data/homepage` | Tidak ada login. Cek kartu layanan dan widget STB |

   Akun, repo Gitea, monitor Uptime Kuma, dan file di `/mnt/data/files` **tidak** ada di repo ini.
   Semuanya ada di **backup** dan dipulihkan dengan [docs/restore.md](docs/restore.md) (bagian 3).

## Backup

- **Apa:** seluruh `/mnt/data` kecuali `docker/` dan cache, dienkripsi dengan restic, disimpan di laptop
  `C:\HOME-backup\restic` (lewat rclone/SFTP, akun khusus `homebackup` yang hanya bisa SFTP ke folder itu).
- **Kapan:** setiap hari 20:00 WIB dan 10 menit setelah boot. Kalau laptop tidak tersambung, backup dilewati
  dan dicoba lagi di jadwal berikutnya. Pemeriksaan integritas setiap Minggu 21:00.
- **Pantau:** monitor "Backup harian" di Uptime Kuma. Merah = tidak ada backup sukses dalam 26 jam, atau backup gagal.
- **Password repo** hanya ada di password manager klien dan di STB (`/root/.config/restic/password`).
  Kalau hilang, backup tidak bisa dibuka.
- **Memulihkan:** [docs/restore.md](docs/restore.md). Rancangan dan alasan teknis: [docs/rancangan-backup.md](docs/rancangan-backup.md).
- **Laptop:** `scripts/laptop/setup-backup-target.ps1` (pasang) dan `remove-backup-target.ps1` (bongkar),
  dijalankan klien sebagai Administrator.

## Perawatan

- **Update paket:** `scripts/update.sh --dry-run` untuk melihat apa yang akan berubah, lalu
  `screen -S update /opt/home/scripts/update.sh` untuk upgrade sungguhan. Update otomatis sengaja dimatikan.
- **Update layanan:** ganti tag image di `services/<nama>/compose.yaml` (selalu versi yang di-pin dan mendukung arm64),
  commit dan push, salin ke STB, lalu `docker compose up -d`. Catat di `docs/log.md`.
- **Mematikan STB:** selalu `ssh stb poweroff` dulu, baru cabut adaptor.
- **Reboot:** hanya dengan izin klien, dan setelah fstab terverifikasi (`findmnt --verify`).
- **Repo:** setiap checkpoint di-commit **dan di-push** ke GitHub (`MufuyuMoku/home`), lalu di-mirror ke Gitea.

## Belum dikerjakan

- **Salinan backup ketiga** di luar tas/laptop, dan enkripsi disk laptop (dibahas terpisah).
- **Persistent journal** (usulan ada di `docs/log.md`).
- **Firewall, akses jarak jauh (Tailscale), USB WiFi, reverse proxy/domain.**
