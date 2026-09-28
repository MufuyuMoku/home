# Project HOME: High Operative Management Environment

> **Status: DRAF.** Fase 0 selesai (2026-09-28). Fase 1 baru disiapkan, belum di-deploy.
> Bagian yang ditandai *TODO* akan dilengkapi setelah langkahnya benar-benar dikerjakan dan diuji.

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
flashing ulang. Karena itu kernel, DTB, bootloader, `/boot`, jaringan, dan SSH tidak disentuh (lihat CLAUDE.md).

## Layanan

| Layanan | Fungsi | Alamat | Status |
|---|---|---|---|
| Homepage | Dashboard: link ke semua layanan + CPU/RAM/suhu | http://192.168.137.202:3000 | disiapkan |
| Uptime Kuma | Monitoring hidup/matinya layanan | http://192.168.137.202:3001 | disiapkan |
| Gitea (SQLite) | Server Git pribadi, mirror repo GitHub | http://192.168.137.202:3002, SSH port 2222 | disiapkan |
| Filebrowser | File manager web untuk `/mnt/data/files` | http://192.168.137.202:8080 | disiapkan |

Setiap layanan ada di `services/<nama>/compose.yaml`, dengan image yang versinya di-pin (semuanya arm64),
`mem_limit`, `restart: unless-stopped`, dan data di `/mnt/data/<nama>/`.

## Struktur repo

```
README.md                  # file ini
CLAUDE.md                  # aturan & rancangan (brief konsultan)
docs/hardware.md           # inventaris hardware
docs/log.md                # catatan perubahan
config/etc/...             # file konfigurasi sistem, jalurnya meniru lokasinya di STB
scripts/fase0.sh           # fondasi (idempoten)
scripts/update.sh          # update paket manual yang aman (--dry-run untuk simulasi)
services/<nama>/           # compose.yaml, .env.example, config layanan
```

Rahasia (password, token) hanya ada di file `.env` di STB, yang tidak pernah di-commit. Yang ada di repo hanya `.env.example`.

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
   Script ini menahan paket kernel/Armbian, mematikan repo Armbian beta, membekukan initramfs,
   mematikan update otomatis, meng-upgrade paket dengan aman, mengatur zona waktu Asia/Jakarta,
   mematikan devmon, memeriksa kartu data di `/mnt/data`, lalu memasang `daemon.json` Docker
   (data-root `/mnt/data/docker`, overlay2, rotasi log) dan drop-in `RequiresMountsFor=/mnt/data`.
   Script berhenti kalau ada yang tidak sesuai, misalnya kalau kartu data belum siap.
5. **Layanan.** *TODO (Fase 1):* untuk setiap layanan, salin `.env.example` → `.env`, isi, lalu
   `docker compose up -d`, dan tes dari browser laptop.

## Perawatan

- **Update paket:** `scripts/update.sh --dry-run` untuk melihat apa yang akan berubah, lalu
  `screen -S update /opt/home/scripts/update.sh` untuk upgrade sungguhan. Update otomatis sengaja dimatikan.
- **Mematikan STB:** selalu `ssh stb poweroff` dulu, baru cabut adaptor.
- **Reboot:** hanya dengan izin klien, dan setelah fstab terverifikasi (`findmnt --verify`).
