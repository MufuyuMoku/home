# Project HOME — High Operative Management Environment

Homelab / workspace pribadi di sebuah STB. Repo ini adalah **sumber kebenaran**: semua yang terpasang di STB harus bisa dibangun ulang dari isi repo ini.

## Peran

- **Klien**: pemilik proyek (Fata). Mengambil keputusan dan melakukan langkah yang menyangkut password/akun.
- **Konsultan**: Claude (chat). Menyusun rancangan dan brief ini.
- **Developer**: kamu (Claude Code). Mengeksekusi rancangan di STB lewat SSH dan mencatatnya di repo.

Klien masih belajar soal server/Linux. Komunikasi dalam **bahasa Indonesia**. Setiap langkah, jelaskan singkat *apa* yang dilakukan dan *kenapa*.

## Hardware & akses

| Hal | Nilai |
|---|---|
| Perangkat | STB Fiberhome HG680P (Amlogic S905X, 4 core ARM64 Cortex-A53) |
| RAM | ~1,88 GB (zram bawaan Armbian) |
| Penyimpanan sistem | eMMC, root `/` 5,7 GB (sekitar setengah sudah terpakai) |
| Penyimpanan data | microSD 128 GB (baru di-quick-format di Windows, belum dipakai) |
| OS | Armbian 25.8 rolling untuk `aml-s9xx-box`, basis Ubuntu noble, kernel 6.12.35-current-meson64 |
| Jaringan | LAN 100 Mbps, dicolok langsung ke laptop Windows. Laptop membagikan jaringan lewat Windows ICS. STB = `192.168.137.202`, laptop = `192.168.137.1` |
| Akses | `ssh stb` dari laptop (key auth, user root) |
| Internet STB | Hanya saat laptop tersambung ke internet (hotspot HP). Tidak ada router. |

**Tidak ada HDMI dan tidak ada router.** Kalau STB gagal boot atau kehilangan jaringan/SSH, klien tidak punya cara untuk memperbaikinya selain flashing ulang. Karena itu aturan di bawah ini mutlak.

## Aturan mutlak

1. **Jangan pernah menyentuh kernel, DTB, atau bootloader.** Paket `linux-image-current-meson64` dan `linux-dtb-current-meson64` sudah di-`apt-mark hold`; jangan di-unhold. Jangan ubah `/boot`, `extlinux`, `uEnv`, atau u-boot. Jangan jalankan `armbian-upgrade`, `armbian-install`, `install-aml.sh`, atau apa pun yang menulis ke eMMC di luar filesystem biasa.
2. **Jangan ubah konfigurasi jaringan atau SSH** (netplan, NetworkManager, `/etc/ssh/`, firewall) tanpa persetujuan klien. Jangan pernah mematikan `sshd`.
3. **Setiap entri `/etc/fstab` wajib memakai `nofail`** dan dipasang berdasarkan UUID. Sebelum mengubah fstab, backup dulu, lalu verifikasi dengan `findmnt --verify` dan `mount -a` sebelum dianggap selesai.
4. **Jangan reboot tanpa izin klien.** Sebelum reboot, pastikan fstab sudah terverifikasi.
5. **Operasi destruktif butuh konfirmasi eksplisit dari klien** (format, hapus data, `docker system prune`, dan sejenisnya). Sebelum memformat, tampilkan `lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL` dan identifikasi microSD dari ukurannya (~119 GB). **eMMC (~7 GB) tidak boleh disentuh.**
6. **RAM terbatas.** Setiap container wajib diberi batas memori (`mem_limit`). Periksa `free -h` sebelum dan sesudah memasang layanan baru. Hanya pakai image yang mendukung `linux/arm64`.
7. **Tidak ada rahasia di repo.** Password dan token disimpan di file `.env` (masuk `.gitignore`); yang di-commit hanya `.env.example`.
8. **Tidak ada yang diekspos ke internet.** Semua layanan hanya untuk jaringan lokal.

## Cara kerja

- Menjalankan perintah di STB: `ssh stb "<perintah>"`, atau `ssh stb` secara interaktif untuk pekerjaan yang panjang.
- Mengirim file: `scp` dari repo di laptop ke `/opt/home/` di STB.
- **Struktur repo:**
  ```
  README.md              # apa itu Project HOME, cara membangun ulang
  CLAUDE.md              # file ini
  docs/hardware.md       # hasil inventaris hardware
  docs/log.md            # catatan perubahan (tanggal, apa, kenapa)
  scripts/               # script setup yang bisa dijalankan ulang
  services/<nama>/compose.yaml
  services/<nama>/.env.example
  ```
- Setiap perubahan di STB harus punya padanannya di repo **dan** satu entri di `docs/log.md`. Commit kecil-kecil dengan pesan yang jelas.
- Data layanan disimpan di microSD: `/mnt/data/<nama-layanan>/`.
- Git identity: sebelum commit pertama, pastikan `git config user.name` dan `git config user.email` **lokal** repo ini adalah akun **MufuyuMoku**, bukan identitas global laptop.

## Fase 0 — Fondasi

Kerjakan berurutan, dan laporkan ke klien setelah setiap poin.

1. **Inventaris.** Jalankan `uname -a`, `cat /etc/os-release`, `lsblk`, `df -h`, `free -h`, `apt-mark showhold`, dan `zramctl`. Tulis hasilnya ke `docs/hardware.md`.
2. **Update paket.** `apt update && apt upgrade` (paket kernel tetap tertahan). Pastikan ulang dengan `apt-mark showhold`.
3. **Zona waktu** `Asia/Jakarta`.
4. **microSD** (butuh konfirmasi klien sebelum format). Format ext4 dengan label `HOMEDATA`, pasang di `/mnt/data` via fstab dengan opsi `defaults,noatime,nofail`. Verifikasi sesuai aturan 3.
5. **Docker.** Pasang Docker Engine + compose plugin (arm64). Pindahkan `data-root` ke `/mnt/data/docker` (eMMC terlalu kecil untuk image). Atur rotasi log di `daemon.json` (misalnya `max-size 10m`, `max-file 3`). Tes dengan `docker run --rm hello-world`.
6. Buat `scripts/fase0.sh` yang merangkum langkah 2–5, supaya bisa dijalankan ulang di STB baru.

**Checkpoint:** laporkan ke klien sebelum lanjut ke Fase 1.

## Fase 1 — Starter kit

Pasang satu per satu. Setelah setiap layanan terpasang, klien mengetesnya dari browser laptop di `http://192.168.137.202:<port>`, baru lanjut ke layanan berikutnya.

| Layanan | Fungsi | Port |
|---|---|---|
| Homepage (gethomepage) | Dashboard beranda: link ke semua layanan + status CPU/RAM/suhu | 3000 |
| Uptime Kuma | Monitoring hidup/matinya layanan | 3001 |
| Gitea (SQLite) | Server Git pribadi, mirror repo GitHub | 3002 (web), 2222 (ssh) |
| Filebrowser | File manager web untuk `/mnt/data/files` | 8080 |

- Setiap layanan: `services/<nama>/compose.yaml`, `mem_limit`, `restart: unless-stopped`, data di `/mnt/data/<nama>/`.
- Homepage: daftarkan semua layanan di atas. Perhatikan pengaturan host yang diizinkan (`HOMEPAGE_ALLOWED_HOSTS`) supaya bisa diakses lewat IP.
- Setelah keempatnya jalan, tulis `README.md`: apa itu Project HOME, daftar layanan, dan cara membangun ulang dari nol.

## Di luar cakupan (jangan dikerjakan dulu)

Tailscale / akses jarak jauh, USB WiFi, reverse proxy / domain, dan ekspos ke internet. Semuanya akan dirancang terpisah oleh konsultan.
