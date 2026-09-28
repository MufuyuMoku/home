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

## 2026-09-28: Fase 0 poin 4 dilanjutkan, kartu data via card reader USB

- **Hasil tes kartu (klien, H2testw di laptop):** 118875 MB ditulis dan diverifikasi tanpa error. Kartu asli dan sehat, jadi error flush sebelumnya berasal dari **slot SD STB**.
- **Keputusan konsultan:** data disk tetap microSD yang sama, tapi lewat **card reader USB (di USB hub)**. Slot SD STB tidak dipakai sama sekali.
- **Identifikasi:** `/dev/sda`, TRAN `usb`, "Generic STORAGE DEVICE", 124,7 GB (243.472.384 sektor dan ID tabel partisi `8e622ce8`, sama dengan kartu saat di slot SD). Tidak ter-mount, dmesg bersih. Klien mengonfirmasi eksplisit: "format /dev/sda".
- **CasaOS (pilihan a):** `systemctl stop casaos-local-storage` (tanpa disable) selama format dan fstab, lalu `start` lagi setelah tes tulis-baca. Setelah dinyalakan, `findmnt -S /dev/sda1` hanya menunjukkan `/mnt/data`.
- **Format** (pengaman: TRAN=usb, ukuran 100–130 GB, tidak ada partisi ter-mount): `wipefs -a /dev/sda1`, `wipefs -a /dev/sda`, `sfdisk` membuat GPT dengan 1 partisi penuh "Linux filesystem", `mkfs.ext4 -F -L HOMEDATA -m 1 /dev/sda1` → UUID `569f0d64-a5d7-48b1-9626-f2da7395efa2`. dmesg tanpa error. (Satu baris pemeriksaan tambahan di script salah sintaks (`[: too many arguments`) dan tidak berefek karena `|| true`. Pengaman utama tetap berjalan.)
- **fstab:** backup di `/root/fase0/backup/fstab` (asli) dan `fstab.<timestamp>`. Baris baru:
  `UUID=569f0d64-a5d7-48b1-9626-f2da7395efa2 /mnt/data ext4 defaults,noatime,nofail,x-systemd.device-timeout=10s 0 2`
  Verifikasi pertama melaporkan 1 error karena `/mnt/data` belum dibuat (urutan script salah, belum ada yang di-mount). Setelah `mkdir /mnt/data` + `systemctl daemon-reload`: `findmnt --verify` 0 error (2 warning `/dev/root` yang normal), `mount -a` exit 0.
- **Tes:** `/mnt/data` root:root 755. File acak 4 MB ditulis, `sync`, drop caches, dibaca ulang → sha256 sama, lalu dihapus. dmesg tanpa error. Tersedia 113 GB.

## 2026-09-28: Fase 0 poin 5 selesai, data-root Docker ke `/mnt/data/docker` (overlay2)

- **Temuan:** Docker 29 di STB memakai *containerd image store* (`driver-type io.containerd.snapshotter.v1`), sehingga image disimpan di `/var/lib/containerd` (eMMC), bukan di `data-root`. Ada juga `/etc/systemd/system/docker.service.d/override.conf` bawaan (`DOCKER_MIN_API_VERSION=1.24`, kemungkinan dari installer CasaOS), yang **tidak disentuh**.
- **Keputusan konsultan (pilihan a):** matikan containerd image store dan kembali ke `overlay2`, sehingga semua data Docker ada di `/mnt/data/docker`.
- **Apa:**
  1. `systemctl stop docker.socket docker`.
  2. `rsync -aHAX /var/lib/docker/ /mnt/data/docker/` (chmod 710), lalu `mv /var/lib/docker /var/lib/docker.old` (cadangan, dihapus setelah uji reboot lulus).
  3. `config/etc/docker/daemon.json` ditambah `"data-root": "/mnt/data/docker"` dan `"features": {"containerd-snapshotter": false}` (log-opts tetap). Divalidasi (`json.tool`, `dockerd --validate`) lalu dipasang. Backup sebelumnya: `/root/fase0/backup/daemon.json.pre-b4`.
  4. Drop-in baru `config/etc/systemd/system/docker.service.d/10-home-requires-data.conf` → `/etc/systemd/system/docker.service.d/` dengan `[Unit] RequiresMountsFor=/mnt/data`, lalu `daemon-reload`. `systemctl show docker` → `RequiresMountsFor=/mnt/data`, dan DropInPaths memuat file baru + `override.conf`.
  5. `systemctl start docker`. Script punya rollback otomatis kalau gagal (tidak terpakai).
- **Verifikasi:** `docker info` → Docker Root Dir `/mnt/data/docker`, Storage Driver `overlay2` (Backing Filesystem extfs, `containerd-snapshotter=false` di journal). `hello-world` percobaan pertama gagal karena jaringan (`connection reset by peer` dari registry-1.docker.io; ping/DNS OK), dan percobaan kedua exit 0. Image masuk ke `/mnt/data/docker`. `/var/lib/containerd` (354265 B), `/var/lib/docker.old` (213053 B), dan pemakaian eMMC **tidak berubah** (selisih 0 byte). Image dihapus, sehingga image dan container 0.
- **Repo:** `.gitattributes` ditambah `config/** eol=lf`.

## 2026-09-28: Uji reboot kedua (izin klien) dan penghapusan `/var/lib/docker.old`

- **Sebelum:** uptime 23 menit, `findmnt --verify` 0 error (2 warning `/dev/root` yang normal), `/dev/sda1` di `/mnt/data`, `ssh`/`NetworkManager`/`docker`/`containerd`/`casaos-local-storage` active, devmon disabled, hold 8, `--failed` kosong, Docker root `/mnt/data/docker` overlay2.
- **Reboot:** `systemctl reboot` pukul 17:57:23. Ping berhenti pada detik ke-10, **kembali pada detik ke-42**, **SSH pada detik ke-45**. `systemd-analyze`: 5,1 s + 27,2 s = 32,3 s.
- **Sesudah:** `is-system-running` = running, boot_id baru. **`findmnt -S /dev/sda1` → hanya `/mnt/data`** (CasaOS tidak me-mount di tempat lain). dmesg: `EXT4-fs (sda1): mounted filesystem 569f0d64-…`, tanpa error. `mnt-data.mount` tercatat sebagai dependensi `docker.service`. Docker active dengan Root `/mnt/data/docker` dan Driver `overlay2`. devmon inactive/disabled, hold 8, zona waktu Asia/Jakarta, `--failed` kosong. RAM available 1,5 GiB, suhu 56 °C, eMMC 48%, `/mnt/data` 113 GB tersedia.
- **Penghapusan (izin klien setelah uji reboot lulus):** `rm -rf /var/lib/docker.old` (288 KB, hanya metadata kosong). Sisa `/var/lib/containerd` (354 KB, dari image store lama) dibiarkan.

## 2026-09-28: Fase 0 poin 6 diperbarui, CLAUDE.md / fase0.sh / README

- **CLAUDE.md:** baris hardware data disk (card reader USB, slot SD tidak dipakai), aturan 5 (identifikasi TRAN=usb 100–130 GB), **aturan 11 baru: slot SD STB tidak dipakai sama sekali**, bagian "Kondisi" (Docker data-root/overlay2/drop-in, fstab kartu data, devmon, CasaOS/Samba/rpcbind belum diputuskan), serta poin 4–5 Fase 0 ditandai selesai.
- **`scripts/fase0.sh`:** bagian 4 sekarang *memeriksa* kartu data (tidak ada mount dari `mmcblk1`, entri fstab `/mnt/data` ber-UUID + `nofail`, `findmnt --verify`, ter-mount dari filesystem `HOMEDATA` di disk USB). Format dan fstab tetap manual, dengan langkah di komentar. Bagian 5 memasang drop-in + `daemon.json`, menolak mengganti data-root kalau Docker lama sudah punya image/container, lalu memverifikasi root, overlay2, dan `RequiresMountsFor`. Uji: `bash -n` OK, dan bagian pemeriksaan 4 dan 5 dijalankan terpisah di STB → lolos. `fase0.sh` utuh tidak dijalankan.
- **README.md:** status Fase 0 selesai, langkah bangun ulang disesuaikan (kartu data manual sebelum `fase0.sh`).

## 2026-09-28: Tindak lanjut audit (1): CasaOS + rclone dimatikan

- **Keputusan konsultan:** stop + disable, **tanpa uninstall dan tanpa menghapus file** (termasuk `override.conf` Docker).
- **Apa:** `systemctl disable --now casaos.service casaos-gateway.service casaos-app-management.service casaos-local-storage.service casaos-message-bus.service casaos-user-service.service rclone.service`. Yang dihapus hanya symlink di `/etc/systemd/system/multi-user.target.wants/`. `casaos-user-service` (exit 2) dan `rclone` (exit 143 = SIGTERM) tercatat `failed` saat di-stop, lalu dibersihkan dengan `systemctl reset-failed <unit>` (hanya catatan status).
- **Kenapa:** tidak ada di rancangan, tumpang tindih dengan Project HOME (mengelola Docker dan disk), dashboard terbuka di port 80, `rclone rcd --rc-no-auth`, dan memakai sekitar 320 MB RAM.
- **Verifikasi:** ketujuh unit inactive/disabled, tidak ada proses casaos/rclone, **port 80 tidak dipakai**. File tetap ada (`/usr/bin/casaos*`, `/usr/bin/rclone`, `/etc/casaos/`, `override.conf`). Docker active, root `/mnt/data/docker` overlay2, `hello-world` OK (image dihapus lagi). `--failed` kosong. RAM available **1503 → 1641 MB**.
- **Cara menyalakan kembali:** `systemctl enable --now rclone.service casaos-message-bus.service casaos-gateway.service casaos-user-service.service casaos-local-storage.service casaos-app-management.service casaos.service` (ingat: `casaos-local-storage` bisa me-mount disk USB).

## 2026-09-28: Tindak lanjut audit (2): Samba, rpcbind, openvpn dimatikan; devmon nologin

- **Apa:** `systemctl disable --now smbd.service nmbd.service samba-ad-dc.service rpcbind.service rpcbind.socket openvpn.service`. systemd juga menghapus symlink alias `smb.service`, `nmb.service`, `samba.service` di `/etc/systemd/system/` (bukan file unit). `usermod -s /usr/sbin/nologin devmon`.
- **Kenapa:** Samba tidak punya share data, rpcbind hanya untuk NFS (tidak dipakai), dan openvpn tidak dipakai. User `devmon` adalah sisa devmon yang sudah dimatikan, jadi tidak perlu shell login.
- **Tidak diubah:** `wpa_supplicant` (akan dipakai untuk USB WiFi).
- **Verifikasi:** keenam unit inactive/disabled. `getent passwd devmon` → `/usr/sbin/nologin`. **Port yang terbuka ke jaringan sekarang hanya TCP 22 (ssh).** `--failed` kosong. RAM available 1641 → 1647 MB.
- **Cara menyalakan kembali:** `systemctl enable --now <unit>` (untuk rpcbind: `rpcbind.socket` dan `rpcbind.service`). Shell devmon: `usermod -s /usr/bin/bash devmon`.

## 2026-09-28: Tindak lanjut audit (3): SSH hanya-key

- **Prasyarat:** klien sudah membackup private key ke media offline.
- **Kondisi awal:** `ssh.socket` enabled (socket activation) + `ssh.service`. `/etc/ssh/sshd_config.d/` kosong. `Include /etc/ssh/sshd_config.d/*.conf` ada di baris 12 `sshd_config`, sebelum `PermitRootLogin yes` (baris 42). Efektif: `permitrootlogin yes`, `passwordauthentication yes`.
- **Apa:** `config/etc/ssh/sshd_config.d/10-home.conf` → `/etc/ssh/sshd_config.d/10-home.conf` berisi `PermitRootLogin prohibit-password` dan `PasswordAuthentication no`. File utama `sshd_config` tidak diubah.
- **Prosedur:**
  - `sshd -t` → OK. `sshd -T` → `permitrootlogin without-password` (alias `prohibit-password`), `passwordauthentication no`, `pubkeyauthentication yes`.
  - **Sesi lama:** ControlMaster SSH ternyata tidak berfungsi di OpenSSH Git-Bash Windows (`mux_client_request_session ... Connection reset`), jadi dipakai koneksi SSH latar belakang (`tail -f file | ssh stb 'exec bash -s'`) yang mengeksekusi perintah tanpa login baru. Terbukti bekerja sebelum dan sesudah reload (pid 8581 yang sama).
  - **Pengaman tambahan:** timer darurat `systemd-run --unit=home-ssh-rollback --on-active=10min` (hapus `10-home.conf` + `systemctl reload ssh`), dibatalkan lewat sesi lama setelah tes lulus.
  - `systemctl reload ssh` (bukan restart). `ssh` dan `ssh.socket` tetap active.
- **Uji koneksi BARU dari laptop:** `ssh stb` (key) → berhasil. `ssh -o PubkeyAuthentication=no stb` → `Permission denied (publickey)`, dan server hanya menawarkan `publickey` (sebelumnya `publickey,password`).
- **Membatalkan:** `rm /etc/ssh/sshd_config.d/10-home.conf && systemctl reload ssh`.

## 2026-09-28: Tindak lanjut audit (4): firewall

- **Ditunda, akan dirancang bersama akses jarak jauh/forum.** Tidak ada perubahan. Saat ini port yang terbuka ke jaringan hanya TCP 22.

## 2026-09-28: Tindak lanjut audit (5): `fase0.sh` diperluas, plus perbaikan bug SIGPIPE

- **`fase0.sh` bagian 5:** `daemon.json` dan drop-in dipasang **sebelum** Docker. Kalau `dockerd` belum ada, Docker dipasang dari repo resmi (keyring `/etc/apt/keyrings/docker.asc`, `/etc/apt/sources.list.d/docker.list` dengan format sama seperti di STB ini, lalu `docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`), sehingga Docker pertama kali menyala langsung dengan `/mnt/data/docker` + overlay2.
- **`fase0.sh` bagian 6 (baru):** 6a CasaOS + rclone `disable --now` (+ `reset-failed`), 6b Samba/rpcbind (service + socket)/openvpn `disable --now`, shell devmon → nologin, `wpa_supplicant` dibiarkan. 6c SSH hanya-key: wajib ada `authorized_keys` yang valid, pasang `10-home.conf`, `sshd -t` (kalau gagal, file dihapus lagi), `systemctl reload ssh`, lalu verifikasi `sshd -T`. Komentar mengingatkan untuk menguji koneksi SSH baru sebelum menutup sesi.
- **Bug ditemukan saat uji:** `sshd -T | grep -q ...` gagal di bawah `set -o pipefail` karena SIGPIPE, walaupun nilainya benar. Pola yang sama di `update.sh` (`dpkg -L | grep -q '^/boot'`) **bisa meloloskan paket yang menyentuh `/boot`** kalau daftar filenya panjang. Semua pola `cmd | grep -q` yang berisiko diganti `grep -q ... < <(cmd)` atau variabel.
- **Uji (tanpa mengubah STB):** `bash -n` OK untuk kedua script. Bagian 6 dijalankan dengan perintah pengubah ditiru → semua unit "sudah mati", SSH "sudah berlaku", exit 0. Bagian pemeriksaan 4+5 → OK. Deteksi `/boot` di bawah pipefail: BSP dan `linux-image-current-meson64` ditolak, `coreutils`/`docker-ce` lolos. `update.sh --dry-run` → OK. **Belum teruji:** pemasangan Docker dari nol (Docker sudah ada di STB ini), dan akan teruji saat membangun STB baru.

## 2026-09-28: Tindak lanjut audit (6): persistent journal, penyelidikan + USULAN (BELUM diterapkan)

**Kondisi sekarang (hanya dibaca):**
- `/etc/systemd/journald.conf` (versi Armbian): `Storage=volatile`, `SystemMaxUse=20M`, `Compress=yes`. Drop-in `/usr/lib/systemd/journald.conf.d/syslog.conf`: `ForwardToSyslog=yes`. Journal hanya ada di `/run/log/journal` (RAM, 4,5 MB setelah 22 menit uptime), jadi **selalu hilang** saat reboot atau mati listrik.
- `armbian-ramlog` (`/etc/default/armbian-ramlog`: `SIZE=50M`, `USE_RSYNC=true`): `/var/log` = zram1 (ext4 50 MB), dengan salinan di eMMC `/var/log.hdd` (bind dari `mmcblk2p2:/var/log`). Sinkronisasi RAM → eMMC (`rsync`, **mengecualikan `journal*`**) hanya terjadi saat `logrotate.service` (drop-in `/etc/systemd/system/logrotate.service`: `ExecStartPre=armbian-ramlog write`, sekali sehari pukul 00:00) dan saat stop/shutdown rapi. `/etc/cron.daily/armbian-ram-logging` langsung keluar karena `logrotate.timer` aktif. Saat sinkron, skrip juga menjalankan `journalctl --flush` dan `journalctl --relinquish-var`.
- Akibatnya kalau listrik putus: journal hilang semua, log teks (`syslog`, dan lainnya) hilang sejak tengah malam terakhir.
- Laju log setelah boot (termasuk aktivitas kerja): `/var/log/syslog` 2,9 MB dalam 22 menit. Laju harian saat idle belum diukur.

**Usulan desain:** journal persisten di **kartu data**, bukan eMMC (eMMC tidak bisa diganti, kartu bisa).
1. `/etc/systemd/journald.conf.d/10-home.conf`:
   `Storage=persistent`, `SystemMaxUse=64M`, `SystemKeepFree=1G`, `SystemMaxFileSize=8M`, `MaxRetentionSec=1month`, `SyncIntervalSec=60s` (default 5 menit; pesan kritis selalu langsung di-sync). Ini mengalahkan `Storage=volatile` di file utama tanpa mengubah file Armbian.
2. Mount unit `var-log-journal.mount`: bind `/mnt/data/journal` → `/var/log/journal`, dengan `Requires=mnt-data.mount`, `After=mnt-data.mount armbian-ramlog.service` (supaya tidak tertutup zram yang di-mount kemudian), `Before=systemd-journal-flush.service`. Kalau kartu tidak ada, mount gagal dan journald jatuh kembali ke RAM, tanpa menulis ke eMMC.
3. Hal yang perlu diuji/diputuskan: interaksi dengan `journalctl --relinquish-var` di `armbian-ramlog` (dipanggil setiap logrotate harian; bisa membuat journald kembali ke RAM sampai flush berikutnya), dan `--flush` di `ExecStop`. Kemungkinan solusi: drop-in yang memanggil `journalctl --flush` lagi setelah `armbian-ramlog write`, atau `XTRA`/konfigurasi ramlog. Perlu diuji dengan reboot dan simulasi logrotate.
4. **Keausan:** batas total 64 MB, file 8 MB, dan sync per 60 detik di microSD 128 GB (sudah 609 MB lifetime writes). Dampaknya sangat kecil. eMMC tidak mendapat tulisan tambahan.
- **Alternatif minimal (tanpa journal persisten):** timer per jam yang menjalankan `armbian-ramlog write`, sehingga log teks yang hilang saat listrik putus paling banyak 1 jam. Tulisan ke eMMC hanya file yang berubah (rsync), tapi journal tetap hilang.
- **Status:** hanya usulan, menunggu desain konsultan.

## 2026-09-28: Tindak lanjut audit (7): uji reboot ketiga (izin klien)

- **Sebelum:** uptime 24 menit, `findmnt --verify` 0 error, `--failed` kosong, port terbuka hanya TCP 22, RAM available 1648 MB.
- **Reboot:** 18:23:06. Ping berhenti pada detik ke-10, **kembali pada detik ke-44**, **SSH dengan key pada detik ke-47**. `systemd-analyze`: 5,1 s + **19,8 s** = 24,8 s (sebelumnya userspace 27,2 s).
- **Sesudah:** `is-system-running` = running. Ke-14 unit yang dimatikan (6 casaos, rclone, smbd, nmbd, samba-ad-dc, rpcbind service+socket, openvpn, devmon) inactive/disabled, tanpa proses tersisa. Shell devmon `/usr/sbin/nologin`. Port terbuka ke jaringan hanya TCP 22. `sshd -T`: `permitrootlogin without-password`, `passwordauthentication no`. Koneksi baru tanpa key → `Permission denied (publickey)`, server hanya menawarkan `publickey`. `/dev/sda1` hanya di `/mnt/data`. Docker root `/mnt/data/docker` overlay2. `ssh`/`NetworkManager`/`docker`/`containerd`/`wpa_supplicant` active. Hold 8, zona waktu Asia/Jakarta, `--failed` kosong, dmesg tanpa error I/O. Suhu 52 °C. eMMC 48%, `/mnt/data` 113 GB tersedia.
- **RAM available:** **1503 MB** (sebelum langkah 1, saat CasaOS dkk. masih jalan) → **1650 MB** (setelah boot tanpa layanan itu), atau **+147 MB**. `used` 417 → 270 MB.
- **CLAUDE.md** bagian "Kondisi" diperbarui (layanan yang dimatikan, SSH hanya-key, port terbuka).

## 2026-09-28: Keputusan konsultan sebelum Fase 1

- **Persistent journal:** ditunda sampai setelah Fase 1, dirancang dan diuji sebagai tugas tersendiri.
- **`/var/lib/containerd`:** dibiarkan permanen (dipakai containerd). Keputusan final.
- **Timer rollback otomatis** untuk setiap perubahan konfigurasi SSH atau jaringan ditetapkan sebagai prosedur standar, dan menjadi **aturan mutlak 12** di CLAUDE.md.

## 2026-09-28: Fase 1 layanan 1, Filebrowser

- **Apa:** `/opt/home/services/filebrowser`: `.env` dari `.env.example` (hanya `TZ`, chmod 600, tidak di-commit). Folder `/mnt/data/files`, `/mnt/data/filebrowser/{database,config}` dibuat dengan pemilik UID/GID 1000 (di host GID 1000 bernama `devmon`; hanya nama). `docker compose up -d` (image `filebrowser/filebrowser:v2.63.23`).
- **Volume:** hanya `/mnt/data/files` → `/srv` sebagai data, ditambah `database` dan `config` miliknya sendiri. **Tidak** seluruh `/mnt/data`.
- **Verifikasi:** `running`, health `healthy`, `restart=unless-stopped`, `mem_limit` 128 MiB (pakai sekitar 14 MiB). Proses berjalan sebagai `uid=1000(user)`. Port: hanya `8080 → 80` (ditambah 22 yang sudah ada).
- **Password admin awal:** dibuat acak oleh Filebrowser dan hanya ada di `docker logs filebrowser`. **Tidak ditulis ke repo atau log ini.** Klien login sebagai `admin` lalu menggantinya.
- **RAM available:** 1677 → 1612 MB. **Kartu data terpakai:** 472K → 37M.
- **TEMUAN, perlu keputusan konsultan:** log Filebrowser menyatakan *"File Browser is being wound down. The project is archived on 2026-09-01, after which there will be no further releases and no security fixes. Known unfixed issues are at https://github.com/filebrowser/filebrowser/security/advisories"*. Tetap dipasang sesuai rancangan (hanya LAN, tidak diekspos), menunggu keputusan apakah dipertahankan atau diganti.
- **Catatan kecil:** stempel waktu log container dalam UTC (image kemungkinan tidak membawa data zona waktu). Tidak berpengaruh ke fungsi.

## 2026-09-28: Fase 1 layanan 1 (ulang), Filebrowser diganti FileBrowser Quantum

- **Keputusan konsultan:** Filebrowser upstream diganti karena proyeknya diarsipkan dan tidak menerima patch keamanan. Klien tidak membuat akun di sana.
- **Pembongkaran:** `docker compose down` (container + network `filebrowser_default` dihapus), `docker rmi filebrowser/filebrowser:v2.63.23`. `/mnt/data/files` dibiarkan. **Sisa yang TIDAK dihapus (menunggu izin klien):** `/mnt/data/filebrowser/` (52K: database + config lama, termasuk akun admin acak yang tidak pernah dipakai) dan `/opt/home/services/filebrowser/` di STB. Di repo, `services/filebrowser/` dihapus (sudah digantikan).
- **Image:** Docker Hub `gtsteffaniak/filebrowser` → "object not found". Image ada di **GHCR** `ghcr.io/gtsteffaniak/filebrowser`. Rilis stabil terbaru `1.5.6-stable` (versi 2.x masih beta). `docker manifest`/registry (tanpa pull): `1.5.6-stable` linux/amd64+arm64 (72 MB), **`1.5.6-stable-slim`** linux/amd64+arm64+arm/v7 (**25 MB**, dipilih; tanpa ffmpeg, jadi tidak ada preview video). User `filebrowser` = UID/GID 1000:1000.
- **Konfigurasi** (sesuai dokumentasi v1.5.x di filebrowserquantum.com): `services/filebrowser-quantum/compose.yaml`: port `8080:80`, `mem_limit 192m`, volume **hanya** `/mnt/data/files:/folder` + `/mnt/data/filebrowser-quantum/data:/home/filebrowser/data`. `config.yaml` (di repo, tanpa password) disalin ke folder data: `server.cacheDir`, satu source `/folder` bernama `files`, `defaultEnabled: true`. Folder dimiliki 1000:1000.
- **Verifikasi:** `healthy`, restart 0, `unless-stopped`, proses `uid=1000(filebrowser)`, port hanya 8080 (+22).
- **RAM container:** idle **34 MiB**. Setelah indexing 5.000 file uji (20 MB di `/mnt/data/files/_uji-index`, lalu dihapus) + restart: **38,9 MiB** (3 sampel, CPU 0%). Di bawah ambang 150 MB. RAM available STB 1659 → 1588 MB. Kartu data terpakai 624K → 59M.
- **Login awal:** `admin` / `admin` (default image, didokumentasikan; tidak ada password di repo). Log first-start: "Resetting admin user to default username and password". Setelah restart dengan database yang sudah ada, pesan itu **tidak** muncul lagi ("Using existing database"), sehingga password yang diganti klien tidak di-reset.
- **Catatan untuk konsultan:** (1) log menunjukkan `SQL Journal Mode: OFF` (database SQLite tanpa jurnal, lebih rentan rusak kalau listrik putus saat menulis). (2) peringatan `cacheDir slow write speed detected: 18.54 MB/s` (microSD; hanya memengaruhi cache preview/upload).
- **Repo:** `CLAUDE.md` tabel Fase 1 (+ catatan upstream tidak dipakai, cadangan SFTP), `README.md`, `services/homepage/config/services.yaml` (nama tampilan).
- **Tes klien:** berhasil. Password admin sudah diganti oleh klien.

## 2026-09-28: Tindak lanjut FileBrowser Quantum

- **Sisa Filebrowser lama dihapus (izin klien):** `rm -rf /mnt/data/filebrowser` (config `settings.json` + `database/filebrowser.db`, 52K) dan `/opt/home/services/filebrowser` (compose, `.env`, `.env.example`). Tidak ada container yang memakainya.
- **"SQL Journal Mode: OFF":** dokumentasi v1.5.x **tidak menyediakan** pengaturan mode jurnal (di v2 hanya ada `server.indexSqlConfig.walMode`, dan itu untuk database index). Tidak ada perubahan config. Hasil pemeriksaan file:
  - `data/database.db` (akun, password, setelan) = **BoltDB** (magic `0xED0CDAED`), bukan SQLite. BoltDB memakai copy-on-write + fsync, sehingga dirancang tahan terhadap mati listrik.
  - Satu-satunya SQLite adalah `data/tmp/sql/index_all.db` (index pencarian di folder cache). Mode jurnal OFF berlaku untuk file ini, dan isinya bisa dibangun ulang dari `/mnt/data/files`.
  - **Risiko** terbatas pada database akun/setelan dan index. File di `/mnt/data/files` tidak terdampak. **Folder `/mnt/data/filebrowser-quantum/data` wajib masuk rancangan backup nanti.**
- **Peringatan kecepatan cacheDir:** diterima konsultan, tidak ada tindakan.

## 2026-09-28: Fase 1 layanan 2, Gitea (SQLite)

- **Apa:** `/opt/home/services/gitea`: `.env` dari `.env.example` (`HOST_IP`, `PUID/PGID` 1000, `TZ`; tanpa rahasia, chmod 600, tidak di-commit). `mkdir /mnt/data/gitea`, lalu `docker compose up -d` (image `gitea/gitea:1.27.3`). Entrypoint image membuat `/data/{git,gitea}` milik UID 1000 dan `/data/ssh` (host key).
- **Verifikasi:** `running`, restart 0, `unless-stopped`, `mem_limit` 384 MiB. HTTP `/` → 200 (halaman instalasi; `INSTALL_LOCK = false` sampai klien menyelesaikan instalasi). Port hanya `3002→3000` (web) dan `2222→22` (git SSH). Port 22 milik STB tidak terpengaruh. `ssh-keyscan -p 2222` → host key ecdsa/rsa/ed25519. Proses `gitea` berjalan sebagai user `git`.
- **`app.ini` (hasil env):** `DB_TYPE = sqlite3`, `PATH = /data/gitea/gitea.db`, `DOMAIN = 192.168.137.202`, `ROOT_URL = http://192.168.137.202:3002/`, `SSH_PORT = 2222`, `SSH_LISTEN_PORT = 22`, `DISABLE_REGISTRATION = true`.
- **RAM:** Gitea sekitar 91 MiB (idle, halaman instalasi). RAM available STB 1580 → 1444 MB. **Kartu data terpakai:** 59M → 350M (image Gitea).
- **Akun admin:** dibuat oleh klien di halaman instalasi (bagian "Administrator Account Settings"). Tidak ada password di repo atau log.
- **Tes klien:** instalasi dan akun admin berhasil. Migrasi dari GitHub gagal: "You cannot import from disallowed hosts…".

## 2026-09-28: Gitea, migrasi GitHub diblokir (DNS64/NAT64) → allowlist eksplisit

- **Diagnosis (hanya membaca):** `[migrations]` tidak ada di `app.ini`, dan tidak ada env `GITEA__migrations__*`, sehingga Gitea memakai aturan bawaan (hanya host "eksternal"). DNS STB = `192.168.137.1` (Windows ICS, diteruskan dari hotspot). Dari STB **dan** dari dalam container, `github.com` → `20.205.243.166` **dan** `64:ff9b::14cd:f3a6` (prefiks **NAT64** 64:ff9b::/96 dari DNS64 hotspot). Pola sama untuk `api.`/`codeload.github.com`/`objects.githubusercontent.com`. STB tidak punya rute IPv6 (hanya link-local), jadi koneksi nyata lewat IPv4: `curl https://github.com` → 200 dari STB, `wget` dari container → OK, ping 1.1.1.1 OK. **Internet dan DNS berfungsi.** Kemungkinan penyebab: Gitea memeriksa setiap alamat hasil DNS, dan alamat NAT64 tidak lolos aturan "eksternal" bawaan. Konfigurasi jaringan STB **tidak diubah**.
- **Perbaikan (disetujui konsultan):** `services/gitea/compose.yaml` ditambah `GITEA__migrations__ALLOWED_DOMAINS: "github.com,*.github.com"` dan `GITEA__migrations__ALLOW_LOCALNETWORKS: "false"`. Backup `app.ini` sebelumnya: `/root/fase0/backup/gitea-app.ini.<timestamp>`. `docker compose up -d` (container dibuat ulang, data tetap).
- **Verifikasi:** `running`, restart 0, HTTP 200. Env container dan `app.ini` `[migrations]` → `ALLOWED_DOMAINS = github.com,*.github.com`, `ALLOW_LOCALNETWORKS = false`. `INSTALL_LOCK = true` (instalasi/akun klien tetap).
- **Tes klien:** migrasi berhasil, mirror `MufuyuMoku/home` berjalan di Gitea.

## 2026-09-28: Repo di-push ke GitHub + aturan push

- **Temuan klien:** mirror Gitea hanya berisi 1 commit, karena semua commit proyek belum pernah di-push ke GitHub.
- **Pemeriksaan sebelum push:** `git status` bersih. Identitas lokal MufuyuMoku `264320223+MufuyuMoku@users.noreply.github.com`, dan seluruh 27 commit (author + committer) memakai identitas itu. Remote `origin` = `https://github.com/MufuyuMoku/home.git`. Tidak ada file `.env`/key/token di riwayat commit.
- **Push:** `git push origin main` → `62a45a7..d9b8c31`, **26 commit ter-push**. `origin/main` = 27 commit, sejajar dengan `main`.
- **Aturan baru di CLAUDE.md ("Cara kerja"):** setiap selesai satu langkah/checkpoint yang dilaporkan ke klien: commit lalu push ke GitHub. Repo yang hanya ada di laptop tidak dianggap tersimpan.
- Push kedua: `d9b8c31..29fe23e`, sehingga GitHub berisi 28 commit. Klien akan menekan "Sync now" di mirror Gitea.

## 2026-09-28: Fase 1 layanan 3, Uptime Kuma

- **Apa:** `/opt/home/services/uptime-kuma`: `.env` dari `.env.example` (hanya `TZ`, chmod 600). `mkdir /mnt/data/uptime-kuma`, lalu `docker compose up -d` (image `louislam/uptime-kuma:2.5.5-slim`).
- **Verifikasi:** `running`, health `healthy`, restart 0, `unless-stopped`, `mem_limit` 384 MiB. HTTP `/` → 302 ke `/setup-database` (menunggu klien memilih database). Port hanya `3001→3001`. Data di `/mnt/data/uptime-kuma` (`docker-tls`, `screenshots`, `upload`; database dibuat setelah setup). Log: versi 2.5.5, Node 22.22.3, tanpa error.
- **RAM:** Uptime Kuma sekitar 109 MiB (Gitea 131 MiB, FileBrowser Quantum 44 MiB). RAM available STB 1451 → **1315 MB** (ambang berhenti 700 MB). **Kartu data terpakai:** 352M → 1011M (image Uptime Kuma).
- **Setup oleh klien:** pilih database **SQLite** (varian `-slim` tidak punya MariaDB bawaan), lalu buat akun admin. Tidak ada password di repo atau log.
- **Tes klien:** berhasil.

## 2026-09-28: Fase 1 layanan 4, Homepage

- **Apa:** `/opt/home/services/homepage`: `.env` dari `.env.example` (`HOMEPAGE_ALLOWED_HOSTS=192.168.137.202:3000`, `PUID/PGID` 1000, `TZ`; chmod 600). Config dari repo (`services/homepage/config/*.yaml`) dipasang ke `/mnt/data/homepage/config` (1000:1000). `docker compose up -d` (image `ghcr.io/gethomepage/homepage:v2.4.0`). Tanpa `docker.sock`.
- **Verifikasi:** `running`, health `healthy`, restart 0, `unless-stopped`, `mem_limit` 256 MiB. Proses `next-server` berjalan sebagai user `node`. Port hanya `3000→3000`.
  - Host check: `http://192.168.137.202:3000/` → 200. Host lain (`evil.example:3000`) → 400 ("Host validation failed"; satu-satunya error di log, dari uji ini).
  - `/api/services` → grup "Layanan": Uptime Kuma, Gitea, FileBrowser Quantum. siteMonitor dari dalam container: 3001 → 302, 3002 → 200, 8080 → 200.
  - Widget resources: CPU OK, `cputemp` 52 °C.
- **RAM:** Homepage sekitar 104 MiB (CPU sempat 79% saat halaman pertama kali dibangun). RAM available STB 1296 → **1180 MB** (ambang 700 MB). **Kartu data terpakai:** 1012M → 1,3G.
- **Total Fase 1 (4 layanan):** RAM available **1659 → 1180 MB** (sebelum layanan pertama → setelah layanan keempat). Container: Homepage 104, Uptime Kuma 128, Gitea 130, FileBrowser Quantum 44 MiB.
- **Tes klien:** berhasil.

## 2026-09-28: Monitor Uptime Kuma (dibuat klien)

- **Pra-cek (dari dalam container `uptime-kuma`):** `http://192.168.137.202:3000|3002|8080` → 200, TCP `192.168.137.202:2222` terbuka.
- **Dibuat klien lewat UI** (dipandu): Homepage (HTTP `:3000`), Gitea (HTTP `:3002`), FileBrowser Quantum (HTTP `:8080`), Gitea SSH (TCP `:2222`), semuanya dengan interval 60 s. Memakai IP STB, bukan `localhost` (di dalam container, `localhost` = container itu sendiri). Notifikasi belum diatur (butuh internet; masuk rancangan akses jarak jauh).
- **Verifikasi (baca `kuma.db` read-only):** 4 monitor aktif, heartbeat terakhir semuanya **UP** (HTTP `200 - OK`, TCP 3 ms).

## 2026-09-28: Uji reboot Fase 1 (izin klien)

- **Sebelum:** uptime 1:32, `findmnt --verify` 0 error, 4 container Up (3 healthy + gitea tanpa healthcheck), `--failed` kosong, RAM available 1156 MB. Port jaringan: 22, 2222, 3000, 3001, 3002, 8080.
- **Reboot:** 19:56:03. Ping berhenti pada detik ke-10, **kembali pada detik ke-47**, **SSH (key) pada detik ke-50**. `systemd-analyze`: 5,1 s + 24,0 s = 29,1 s.
- **Sesudah:**
  - **Keempat container menyala otomatis** (`unless-stopped`), restart count 0, semuanya start 19:56:20 WIB. Docker aktif pada detik ke-29,1 sejak boot, **setelah** `mnt-data.mount` (8,8 s).
  - HTTP: 3000 → 200, 3001 → 302, 3002 → 200, 8080 → 200. `ssh-keyscan -p 2222` → host key. Port sama seperti sebelum reboot.
  - `/dev/sda1` di `/mnt/data`, Docker root `/mnt/data/docker` overlay2, SSH `passwordauthentication no` / `permitrootlogin without-password`, hold 8, `--failed` kosong, dmesg tanpa I/O error/OOM.
  - Uptime Kuma: keempat monitor **UP** (12:58 UTC = 19:58 WIB).
- **Temuan kecil:** Homepage sempat `unhealthy`. Dua healthcheck pertama (19:57:36, 19:57:49) melewati timeout 3 s saat load boot tinggi (load 3,5, empat container start bersamaan). Sejak 19:58:04 lulus terus, dan healthcheck manual 0,04 s. Tidak ada restart. Tidak ada tindakan (opsional nanti: `start_period` lebih panjang di compose).
- **RAM setelah reboot:** available **1206 MB**. Container: Homepage 177 MiB (dari batas 256), Uptime Kuma 198 MiB (384), Gitea 202 MiB (384), FileBrowser Quantum 67 MiB (192). Lebih tinggi daripada setelah pemasangan pertama (104/128/130/44). **Homepage sekitar 69% dari `mem_limit`, perlu dipantau.** Suhu 55 °C. eMMC 48%, `/mnt/data` 1,3G terpakai.

## 2026-09-28: Homepage, mem_limit 384m + healthcheck start_period 60s

- **Keputusan konsultan:** Homepage `mem_limit` 256m → **384m**, healthcheck dengan `start_period` 60 s. Gitea dan Uptime Kuma cukup dipantau (tidak diubah).
- **Apa:** `services/homepage/compose.yaml` ditambah blok `healthcheck` eksplisit, dengan perintah sama seperti bawaan image (`wget --spider -Y off http://127.0.0.1:$$PORT/api/healthcheck`, interval 10s, timeout 3s, retries 3). Yang berubah hanya `start_period: 60s` (bawaan 20s). `docker compose up -d` (container dibuat ulang; config di `/mnt/data/homepage/config` tetap).
- **Uji restart:** `docker inspect` → `StartPeriod` 60 s, `Memory` 402653184 (384 MiB), `$PORT` terbaca benar. `docker restart homepage`: `starting` (0–16 s) → **`healthy` pada 19 s**, tanpa `unhealthy`. Riwayat: dua healthcheck pertama timeout (exit -1) saat startup, tapi jatuh di dalam start_period sehingga tidak dihitung. HTTP 200. RAM 101 MiB.
- **Repo:** `docs/rancangan-backup.md` (rancangan konsultan) ditambahkan ke repo.
