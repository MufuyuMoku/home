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
