# Rancangan Backup — Project HOME

Disusun konsultan. Taruh file ini di `docs/rancangan-backup.md`. Semua aturan di CLAUDE.md tetap berlaku.

## Tujuan

Isi layanan di kartu data harus bisa dipulihkan kalau kartu rusak, file terhapus, atau data korup. Tujuan backup adalah **laptop klien**, lewat kabel STB–laptop (Windows ICS). Tidak ada cloud dan tidak ada disk tambahan.

**Risiko yang diterima klien secara sadar:** kalau STB dan laptop hilang bersamaan (misalnya tas hilang), data non-kode ikut hilang. Kode sudah aman di GitHub.

## Keputusan tetap

| Hal | Keputusan |
|---|---|
| Alat | **restic**, dari repo Ubuntu (apt) di STB |
| Tujuan | Laptop Windows lewat **SFTP** (OpenSSH Server bawaan Windows) |
| Folder di laptop | `C:\HOME-backup\` (repo restic di `C:\HOME-backup\restic`) |
| Yang dibackup | Seluruh `/mnt/data` **kecuali** `/mnt/data/docker` (image bisa diunduh ulang) dan folder cache/index FileBrowser Quantum (`tmp/`) |
| Konsistensi | Container yang punya database (Gitea, Uptime Kuma, FileBrowser Quantum) di-**stop** selama snapshot, lalu dinyalakan lagi. Homepage tidak perlu di-stop. |
| Jadwal | systemd timer: sekali sehari + 10 menit setelah boot, `Persistent=true` |
| Retensi | `--keep-daily 7 --keep-weekly 4 --keep-monthly 6`; `prune` seminggu sekali |
| Batas ukuran | Kalau ukuran repo restic melewati **15 GB**, backup tetap berjalan tapi statusnya dilaporkan gagal (lihat pemantauan) supaya klien tahu |
| Pemantauan | Monitor **Push** di Uptime Kuma: script memanggil URL push hanya kalau backup sukses. Kalau tidak ada sinyal selama 26 jam, monitor menjadi merah. |
| Pemeriksaan integritas | `restic check --read-data-subset=5%` seminggu sekali |

## Bagian A — Laptop (dikerjakan KLIEN, dipandu Claude Code)

Ini mengubah pengaturan Windows, jadi Claude Code **tidak** menjalankannya sendiri. Claude Code menulis `scripts/laptop/setup-backup-target.ps1` beserta penjelasannya. Klien membaca script itu, lalu menjalankannya di PowerShell **sebagai Administrator**.

Isi yang wajib ada:

1. Pasang fitur Windows **OpenSSH Server**. Service `sshd` diset Automatic.
2. Buat **akun lokal khusus** `homebackup`: user standar, bukan admin. Password-nya acak dan panjang, dibuat oleh script, **tidak ditampilkan, dan tidak disimpan di mana pun** (akun ini hanya login dengan key).
3. Buat `C:\HOME-backup\restic`, dengan izin: hanya `homebackup`, `SYSTEM`, dan `Administrators`.
4. Tambahkan blok ini ke `C:\ProgramData\ssh\sshd_config` (backup dulu file aslinya):
   ```
   Match User homebackup
       ForceCommand internal-sftp
       ChrootDirectory C:\HOME-backup
       PasswordAuthentication no
       AllowTcpForwarding no
       X11Forwarding no
       PermitTTY no
   ```
   Pastikan juga akun lain di laptop **tidak bisa** login SSH dengan password (`PasswordAuthentication no` secara global).
5. **Firewall:**
   - nonaktifkan rule bawaan `OpenSSH-Server-In-TCP` yang membuka port 22 untuk semua jaringan,
   - buat rule baru yang mengizinkan TCP 22 **hanya dari `192.168.137.0/24`**.

   Di WiFi sekolah atau hotspot mana pun, port 22 laptop harus tertutup.
6. Public key backup dari STB (lihat Bagian B) dipasang di `C:\Users\homebackup\.ssh\authorized_keys`, dengan izin file yang benar untuk OpenSSH di Windows.
7. Verifikasi dari STB: `sftp` sebagai `homebackup` berhasil dan hanya melihat folder `restic`, login dengan password ditolak, dan shell ditolak.

Sediakan juga script kebalikannya, `scripts/laptop/remove-backup-target.ps1`, untuk membongkar semua perubahan di atas.

## Bagian B — STB (dikerjakan Claude Code)

1. Pasang `restic` dari apt.
2. Buat key SSH khusus backup: `/root/.ssh/backup_ed25519` (tanpa passphrase, izin 600). Tambahkan entri di `/root/.ssh/config` untuk host `laptop-backup` (192.168.137.1, user `homebackup`, key tersebut). Tampilkan **public key**-nya untuk Bagian A langkah 6.
3. **Password repo restic dibuat dan dimasukkan oleh KLIEN, bukan oleh Claude Code.** Klien menjalankan sendiri perintah berikut lewat `ssh stb`, lalu mengetik password tanpa terlihat di layar:
   ```
   install -d -m 700 /root/.config/restic && read -rs P && printf '%s' "$P" > /root/.config/restic/password && chmod 600 /root/.config/restic/password && unset P
   ```
   ⚠️ Password ini **wajib** disimpan klien di password manager. Kalau hilang, backup tidak bisa dibaca oleh siapa pun, termasuk klien sendiri.
4. `restic init` ke `sftp:laptop-backup:/restic`.
5. Script `scripts/backup.sh` (disalin ke `/opt/home/scripts/`). Urutannya:
   - cek kartu data ter-mount dan laptop terjangkau; kalau tidak, keluar dengan status "dilewati", bukan gagal,
   - stop container database → `restic backup` dengan daftar exclude → start container lagi (**selalu** dinyalakan kembali, termasuk saat backup gagal: gunakan `trap`),
   - `restic forget` sesuai retensi (prune hanya pada hari Minggu),
   - cek ukuran repo (batas 15 GB),
   - panggil URL push Uptime Kuma kalau sukses. URL push disimpan di `/root/.config/restic/push-url` (izin 600), **bukan di repo**.
   - Log ringkas ke journal.
6. Unit `home-backup.service` + `home-backup.timer`, serta `home-check.timer` mingguan untuk `restic check`. Semua unit disimpan di repo.
7. Monitor Push di Uptime Kuma dibuat **oleh klien** (dipandu), dengan interval heartbeat 26 jam.
8. Hindari pola `| grep -q` di bawah `set -o pipefail` (pelajaran dari `update.sh`).

## Bagian C — Uji pemulihan (wajib, backup belum dianggap ada sebelum ini lulus)

1. Jalankan backup manual. Snapshot pertama harus sukses dan monitor Push harus hijau.
2. Buat file uji di `/mnt/data/files`, jalankan backup, hapus file itu, lalu **pulihkan** dari snapshot. Isinya harus identik (checksum).
3. Pulihkan snapshot terbaru secara utuh ke `/mnt/data/restore-test/`. Bandingkan jumlah file dan checksum dengan aslinya (untuk container yang di-stop), jalankan `PRAGMA integrity_check` pada setiap database SQLite hasil pulihan, lalu hapus `restore-test`.
4. Tulis `docs/restore.md`: langkah memulihkan satu file, satu layanan, dan seluruh kartu data ke kartu baru. Bahasanya harus bisa diikuti klien sendiri.

## Aturan tambahan untuk CLAUDE.md

- Layanan baru yang menyimpan data di `/mnt/data` wajib masuk cakupan backup dan uji pemulihan.
- Tidak ada password, URL push, atau key yang masuk ke repo.
- Perubahan pengaturan laptop hanya lewat script yang dijalankan klien sendiri.

## Di luar cakupan

Salinan ketiga di luar tas, cloud, enkripsi disk laptop, dan pembersihan dual boot laptop. Semuanya akan dibahas terpisah.
