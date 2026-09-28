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
- **Rencana `scripts/update.sh` (dibuat di poin 6):** cek internet, lalu `apt-get update`, lalu simulasi dan tolak kalau ada paket dari repo non-Ubuntu/Docker atau yang memiliki file di `/boot`. Setelah itu potret md5 `/boot`, upgrade dengan `--force-confdef --force-confold` (disarankan di dalam `screen`), bandingkan `/boot`, dan cek `apt-mark showhold` serta layanan `ssh`/`NetworkManager`/`docker`. Terakhir, jalankan `apt-get clean`.

## 2026-09-28: Poin 2 susulan, `apt-get clean`

- **Apa:** `apt-get clean` (disetujui klien). Cache `/var/cache/apt/archives` turun dari 349 MB ke 28 KB, root `/` kembali ke 47% (sisa 3,1 GB).
- **Kenapa:** eMMC kecil, dan file installer bekas tidak diperlukan lagi. Langkah ini ditambahkan ke rencana `scripts/update.sh`.

## 2026-09-28: Fase 0 poin 3, zona waktu

- **Apa:** `timedatectl set-timezone Asia/Jakarta`. `/etc/localtime` sekarang menunjuk ke `/usr/share/zoneinfo/Asia/Jakarta`. Jam sistem tetap sinkron, dan RTC tetap UTC.
- **Kenapa:** supaya jam di log dan jadwal sesuai WIB.

## 2026-09-28: Uji reboot terkendali (izin klien khusus untuk langkah ini)

- **Kenapa:** membuktikan STB bisa boot dan SSH kembali setelah perubahan poin 2–3, sebelum fstab disentuh di poin 4.
- **Sebelum:** uptime 1:34, `ssh`/`NetworkManager`/`docker` active, hold 8 paket, `systemctl --failed` kosong. `findmnt --verify`: 0 error, 2 warning tentang `/dev/root` (normal di Armbian: `/dev/root` adalah alias dari parameter kernel, bukan file device). fstab tidak diubah.
- **Reboot:** `systemctl reboot` pukul 10:56:13 WIB. Dipantau dari laptop dengan ping setiap detik:
  - ping berhenti pada detik ke-6,
  - **ping kembali pada detik ke-37**,
  - **SSH bisa dipakai pada detik ke-40**.
  - `systemd-analyze`: 5,2 s (kernel) + 27,5 s (userspace) = 32,7 s.
- **Sesudah:** uptime ter-reset (boot_id berubah), kernel tetap `6.12.35-current-meson64`, `ssh`/`NetworkManager`/`docker` active, hold tetap 8 paket, zona waktu `Asia/Jakarta (WIB, +0700)`, `is-system-running` = `running`, `systemctl --failed` kosong. RAM available 1,5 GiB, suhu 57 °C.
- **Catatan:** setelah reboot microSD tidak ter-mount. `devmon` aktif, tapi hanya memasang media saat kartu dicolok (hotplug), tidak saat boot. Tidak berpengaruh, karena devmon akan dimatikan di poin 4.

## 2026-09-28: Fase 0 poin 4, microSD (TERHENTI karena I/O error)

- **Identifikasi:** microSD = `/dev/mmcblk1` (116,1 GiB, jenis kernel `SD`, 1 partisi exFAT `Moku`, tidak ter-mount). eMMC = `/dev/mmcblk2` (7,3 GiB, jenis `MMC`), tidak disentuh. Klien mengonfirmasi eksplisit: "format /dev/mmcblk1p1". Kode tipe partisi dibiarkan (7).
- **Langkah 1 (selesai):** `systemctl disable --now devmon@devmon.service`, sehingga devmon inactive + disabled. Tidak ada mount di `/media/devmon`. Tersisa folder kosong `/media/devmon/{BOOT,Moku}`, dibiarkan.
- **Langkah 2 (GAGAL):** `wipefs -a /dev/mmcblk1p1` → `failed to erase exfat magic string at offset 0x00000003: Input/output error`. `mkfs` tidak dijalankan.
  - dmesg: `I/O error, dev mmcblk1, sector 0 op 0x1:(WRITE) flags 0x800 phys_seg 0`. Artinya yang gagal adalah permintaan *flush* (mengosongkan cache kartu), bukan penulisan data biasa.
  - Setelah error, `blkid -p` tidak lagi menemukan tanda exFAT di `mmcblk1p1`, jadi kemungkinan sebagian penulisan sudah masuk.
  - Kartu: SDXC high-speed, `manfid 0x00009f`, `oemid 0x5449`, `name 00000`, tanggal 06/2023. Flag read-only 0.
- **Status:** berhenti dan dilaporkan ke klien. fstab belum disentuh.
- **Keputusan konsultan:** **poin 4 tertunda, menunggu hasil tes kartu.** Klien mencabut microSD dan mengetesnya di laptop dengan H2testw. `mmcblk1` tidak boleh disentuh sampai hasil tes dibawa kembali. Kalau hasilnya bersih, kartu yang sama kemungkinan dipakai lewat card reader USB (jalur penyimpanan USB, bukan slot SD), dengan rancangan fstab yang sama tapi device berbeda. Pemindahan `data-root` Docker (poin 5) ikut ditunda sampai poin 4 selesai.

## 2026-09-28: Fase 0 poin 5 (sebagian), rotasi log Docker

- **Apa:** memasang `/etc/docker/daemon.json` (sumber di repo: `config/etc/docker/daemon.json`, dikirim lewat `/opt/home/config/etc/docker/`) dengan `log-driver json-file`, `max-size 10m`, `max-file 3`. Sebelumnya file ini belum ada, jadi tidak ada yang perlu dibackup, dan log container tidak dibatasi.
- **Kenapa:** tanpa batas, log container bisa terus membesar sampai eMMC penuh.
- **Validasi:** file ber-LF, `python3 -m json.tool` → valid, `dockerd --validate` → `configuration OK`. `systemctl restart docker` → active.
- **Tes:** `docker run --rm hello-world` → exit 0, "Hello from Docker!". Container baru terbukti memakai `{"Type":"json-file","Config":{"max-file":"3","max-size":"10m"}}` (dicek dengan `docker create` + `docker inspect`, lalu dihapus). Image `hello-world` dihapus, sehingga image dan container kembali 0. Percobaan pertama sempat terpotong (exit 141) karena output di-pipe ke `head`, dan tesnya diulang dengan benar.
- **Repo:** `.gitattributes` ditambah `*.json eol=lf`.
- **Ditunda:** pemindahan `data-root` ke `/mnt/data/docker` menunggu poin 4. Data-root masih `/var/lib/docker` (kosong). Root `/` 48%, RAM available 1,4 GiB.

## 2026-09-28: Fase 0 poin 6, `scripts/fase0.sh` dan `scripts/update.sh`

- **Apa:** dua script idempoten. Keduanya berhenti (exit ≠ 0) kalau ada kondisi yang tidak sesuai. Disalin ke STB di `/opt/home/scripts/`.
  - `update.sh [--dry-run]` melakukan: pemeriksaan awal (8 hold wajib, repo beta nonaktif, `update_initramfs=no`, internet, dan wajib di dalam screen/tmux untuk upgrade sungguhan), `apt-get update`, lalu simulasi `apt-get -s upgrade`. Paket ditolak kalau namanya `armbian-*`/`linux-image-*`/`linux-dtb-*`/`*u-boot-*`, kalau versi kandidatnya bukan dari `ports.ubuntu.com`/`download.docker.com`, kalau memiliki file di `/boot`, atau kalau simulasi akan menghapus paket. Setelah itu: potret md5 `/boot`, upgrade `--force-confdef --force-confold`, `apt-get clean`, bandingkan `/boot`, cek hold dan layanan `ssh`/`NetworkManager`/`docker`. Log di `/root/home-update/`.
  - `fase0.sh` melakukan: inventaris, hold, repo beta, initramfs, auto-update mati, upgrade (memanggil `update.sh`), zona waktu, devmon mati, `daemon.json`, dan tes `hello-world`. Backup file asli hanya dibuat sekali di `/root/fase0/backup/`. **TODO:** format kartu data + fstab (poin 4), pemasangan Docker untuk STB baru (belum diotomatiskan, script berhenti kalau Docker tidak ada), dan pemindahan `data-root`.
- **Uji:** `bash -n` OK untuk keduanya, file ber-LF. `update.sh --dry-run` → exit 0 ("tidak ada paket yang perlu di-upgrade"). Argumen salah → exit 2. Upgrade tanpa screen → ditolak (exit 1). Penyaring paket diuji terpisah dengan daftar contoh; uji ini menemukan bug (URL `http://ports.ubuntu.com` tanpa `/` ikut ditolak), yang sudah diperbaiki. Setelah itu `docker-ce`/`curl`/`containerd.io` lolos, dan `armbian-config`/`linux-image-*`/BSP ditolak. **`fase0.sh` tidak dijalankan** (sesuai instruksi).

## 2026-09-28: STB mati sekitar 12:00 dan menyala 17:34, **power dicabut manual oleh klien**

- **Apa:** SSH/ping gagal sekitar 17:33. STB kembali 17:34 dengan boot ID baru. `last` tidak mencatat shutdown normal, dan jam boot mundur ke 12:00 (STB tanpa baterai RTC memakai waktu terakhir yang tersimpan). Log sesi sebelumnya hilang karena journal disimpan di RAM (zram).
- **Penyebab (konfirmasi klien):** adaptor daya dicabut manual sekitar 12:00 karena STB ditinggal, lalu dicolok lagi sekitar 17:34. STB memakai adaptor sendiri, bukan USB laptop. Bukan masalah sistem.
- **Setelah boot:** `ssh`/`NetworkManager`/`docker` active, `systemctl --failed` kosong, RAM available 1,5 GiB, suhu 44 °C.
- **Kesepakatan:** mulai sekarang klien mematikan STB dengan `ssh stb poweroff` sebelum mencabut daya.
- **Usulan (disetujui sebagai rencana, BELUM diterapkan):** persistent journal supaya log tidak hilang saat mati mendadak. Dirancang konsultan setelah poin 4 (kemungkinan disimpan di kartu data, bukan eMMC).

## 2026-09-28: Persiapan Fase 1 (tanpa deploy)

- **Apa:** `services/{homepage,uptime-kuma,gitea,filebrowser}/compose.yaml` + `.env.example`, config Homepage (`services/homepage/config/*.yaml`), dan `.gitignore` (`.env` tidak pernah di-commit). Disalin ke STB `/opt/home/services/` hanya untuk validasi.
- **Image di-pin** (dicek dengan `docker manifest inspect` dan membaca config image dari registry, **tanpa pull**):

  | Image | arm64 | Terkompresi | mem_limit | Port | Data |
  |---|---|---|---|---|---|
  | `ghcr.io/gethomepage/homepage:v2.4.0` | ✅ | 75 MB | 256m | 3000 | `/mnt/data/homepage/config` |
  | `louislam/uptime-kuma:2.5.5-slim` | ✅ | 171 MB | 384m | 3001 | `/mnt/data/uptime-kuma` |
  | `gitea/gitea:1.27.3` | ✅ | 66 MB | 384m | 3002, 2222 | `/mnt/data/gitea` |
  | `filebrowser/filebrowser:v2.63.23` | ✅ | 15 MB | 128m | 8080 | `/mnt/data/files`, `/mnt/data/filebrowser/{database,config}` |

  Total sekitar 330 MB terkompresi (perkiraan 0,8–1 GB setelah diekstrak). Uptime Kuma memakai varian `-slim` (tanpa MariaDB/Chromium bawaan; versi penuh 574 MB).
- **Keputusan desain:** Homepage tidak diberi `docker.sock` (setara akses root). Status layanan memakai `siteMonitor`. Gitea: SQLite, `DISABLE_REGISTRATION=true` (admin dibuat di halaman instalasi). Filebrowser berjalan sebagai UID 1000 (password admin awal ada di `docker logs`). Port dipublikasikan ke semua antarmuka STB, dan hanya bisa dijangkau dari LAN karena tidak ada router.
- **Validasi:** semua file LF. `docker compose config --quiet` valid untuk keempatnya (dengan `--env-file .env.example`). YAML config Homepage bisa di-parse. Image/container di STB tetap 0.

## 2026-09-28: Audit keamanan (hanya membaca, TIDAK ada yang diubah)

Perintah: `ss -tlnp`, `ss -ulnp`, `systemctl list-units/list-unit-files`, `sshd -T`, `testparm -s`, dan pemakaian memori per unit.

**Port yang terbuka ke jaringan (bukan hanya localhost):**

| Port | Proses | Catatan |
|---|---|---|
| TCP 22 | sshd | dibutuhkan |
| TCP 80 | `casaos-gateway` | **CasaOS** (dashboard home-server pihak ketiga, bukan bagian rancangan) |
| TCP 139, 445 / UDP 137, 138 | `smbd`, `nmbd` (Samba) | tidak ada share selain printer bawaan; `map to guest = Bad User` |
| TCP/UDP 111 | `rpcbind` | hanya dibutuhkan untuk NFS |

Port lain hanya di localhost (CasaOS internal, `systemd-resolved`, `chronyd`).

**Temuan (usulan saja; keputusan di klien/konsultan):**
1. **CasaOS terpasang dan berjalan**: 6 layanan `casaos*` + `rclone.service` (`rclone rcd` via unix socket dengan `--rc-no-auth`), memakai sekitar **320 MB RAM** (casaos-app-management 125, local-storage 64, message-bus 35, casaos 18, gateway 12, user-service 9, rclone 58). CasaOS bisa mengelola Docker dan disk (`casaos-local-storage` berpotensi **auto-mount disk USB**, mirip devmon), sehingga tumpang tindih dengan rancangan Project HOME. Dashboard-nya terbuka di port 80. Tidak dipasang lewat dpkg; config ada di `/etc/casaos/`.
2. **Samba** (`smbd`, `nmbd`): tidak ada share data. Sepertinya tidak dibutuhkan.
3. **`rpcbind`**: tidak ada NFS. Sepertinya tidak dibutuhkan.
4. **SSH:** `PermitRootLogin yes` (eksplisit di `sshd_config:42`) dan `PasswordAuthentication yes` (default), sementara root punya password. Login password dari LAN masih mungkin. Usulan: key-only. **Butuh persetujuan (aturan 2)** dan harus diuji hati-hati.
5. `unattended-upgrades.service` running: ini hanya penjaga saat shutdown. Dengan `APT::Periodic::Unattended-Upgrade "0"` tidak ada upgrade otomatis. Timer `apt-daily*` masih aktif, tapi keduanya membaca setelan `APT::Periodic` yang sudah 0.
6. Lain-lain yang kemungkinan tidak dibutuhkan: `openvpn.service` (enabled, tidak running), `samba-ad-dc.service` (enabled, tidak running), `wpa_supplicant` (tidak ada WiFi dipakai), `vnstat` (statistik trafik, ringan 2 MB), user `devmon` dengan shell bash (sisa devmon).
7. Tidak ada firewall aktif (`INPUT ACCEPT`). Sesuai aturan 2, firewall tidak disentuh tanpa persetujuan.
