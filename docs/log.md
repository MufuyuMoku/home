# Log perubahan

Format: tanggal, apa yang dilakukan, kenapa. Entri terbaru di bawah.

## 2026-09-28: Fase 0 poin 1, inventaris

- **Apa:** menjalankan `uname -a`, `cat /etc/os-release`, `lsblk`, `df -h`, `free -h`, `apt-mark showhold`, `zramctl` di STB. Hasil di `docs/hardware.md`.
- **Kenapa:** mencatat kondisi awal STB sebelum ada perubahan.
- **Perubahan di STB:** tidak ada (hanya membaca).
- **Temuan:** microSD (`mmcblk1`, exFAT, label `Moku`) di-auto-mount oleh layanan `devmon` ke `/media/devmon/Moku`. Isinya hanya `System Volume Information`. Zona waktu masih `Etc/UTC`.

## 2026-09-28: `.gitattributes` dan keputusan devmon

- **Apa:** menambah `.gitattributes` supaya `*.sh`, `*.yaml`, `*.yml`, `*.conf`, dan `.env*` selalu memakai akhir baris LF.
- **Kenapa:** Git di laptop Windows mengubah akhir baris menjadi CRLF, dan script/konfigurasi dengan CRLF bisa gagal dijalankan di STB.
- **Keputusan (konsultan, via klien):** di poin 4, layanan `devmon` akan dimatikan dan dinonaktifkan (`systemctl disable --now`) sebelum microSD di-unmount dan diformat. Alasannya, penyimpanan server hanya boleh terpasang lewat fstab di `/mnt/data`. Format tetap menunggu konfirmasi klien.

## 2026-09-28: Fase 0 poin 2, update paket

- **Pemeriksaan awal:** internet OK (`ping 1.1.1.1`). `apt update` menunjukkan ~230 paket bisa di-upgrade. Tidak ada paket `linux-u-boot-*`. Temuan: paket BSP memiliki file di `/boot`, upgrade biasa akan membangun ulang initramfs di `/boot`, repo Armbian yang dipakai adalah beta (nightly, 25.8 → 26.11-trunk), `unattended-upgrades` aktif, dan Docker ternyata sudah terpasang. Upgrade dihentikan dan dilaporkan ke klien/konsultan.
- **Keputusan konsultan, lalu dikerjakan** (backup file asli di STB: `/root/fase0/backup/`):
  - `apt-mark hold armbian-bsp-cli-aml-s9xx-box-current armbian-config armbian-firmware armbian-plymouth-theme armbian-zsh base-files`. Kenapa: BSP menulis ke `/boot`, paket armbian lain dibekukan di versi yang terbukti jalan.
  - Semua baris `/etc/apt/sources.list.d/armbian.sources` (`beta.armbian.com`) diberi komentar. Kenapa: repo nightly tidak stabil.
  - `update_initramfs=no` di `/etc/initramfs-tools/update-initramfs.conf`. Kenapa: kernel sudah dibekukan, jadi initramfs ikut dibekukan dan `/boot` tidak disentuh.
  - File baru `/etc/apt/apt.conf.d/99home-no-auto-upgrades` men-set `APT::Periodic::Update-Package-Lists "0"` dan `APT::Periodic::Unattended-Upgrade "0"`. Kenapa: update tidak boleh terjadi di luar kendali. **Cara membalik:** hapus file itu.
- **Simulasi** (`apt-get -s upgrade`): 227 paket, semuanya dari `ports.ubuntu.com` atau `download.docker.com`, tidak ada yang memiliki file di `/boot`. `armbian-config` (dari repo `github.armbian.com/configng`) tertahan.
- **Upgrade:** dijalankan dalam `screen` dengan `DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade`. Log di STB: `/root/fase0/upgrade.log`. Hasil: 227 upgraded, exit 0. Log mencatat `update-initramfs: Not updating initramfs.` (pembekuan bekerja).
- **Verifikasi:**
  - `/boot`: md5 seluruh 168 file identik dengan potret sebelum upgrade (`/root/fase0/boot-md5-{before,after}.txt`). Satu-satunya perbedaan di `ls -la /boot` adalah baris `..` (folder `/`), karena paket Ubuntu membuat folder penanda usrmerge `/bin.usr-is-merged`, `/lib.usr-is-merged`, dan `/sbin.usr-is-merged`.
  - `apt-mark showhold`: 8 paket (2 kernel/DTB + 6 di atas).
  - `ssh`, `NetworkManager`, `docker`, `containerd`: active. Tidak ada `reboot-required`.
  - Docker 29.8.1, Compose v5.5.1. RAM available 1,4 GiB. Root 55% terpakai (sisa 2,6 GB).
- **CLAUDE.md** diperbarui: bagian "Kondisi paket & update", aturan mutlak 9 (repo beta) dan 10 (hold/initramfs/update otomatis), poin 5 menjadi konfigurasi ulang Docker, dan poin 6 ditambah `scripts/update.sh`.
- **Rencana `scripts/update.sh` (dibuat di poin 6):** cek internet, lalu `apt-get update`, lalu simulasi dan tolak kalau ada paket dari repo non-Ubuntu/Docker atau yang memiliki file di `/boot`. Setelah itu potret md5 `/boot`, upgrade dengan `--force-confdef --force-confold` (disarankan di dalam `screen`), bandingkan `/boot`, dan cek `apt-mark showhold` serta layanan `ssh`/`NetworkManager`/`docker`.
