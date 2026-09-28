# Log perubahan

Format: tanggal, apa yang dilakukan, kenapa. Entri terbaru di bawah.

## 2026-09-28: Fase 0 poin 1, inventaris

- **Apa:** menjalankan `uname -a`, `cat /etc/os-release`, `lsblk`, `df -h`, `free -h`, `apt-mark showhold`, `zramctl` di STB. Hasil di `docs/hardware.md`.
- **Kenapa:** mencatat kondisi awal STB sebelum ada perubahan.
- **Perubahan di STB:** tidak ada (hanya membaca).
- **Temuan:** microSD (`mmcblk1`, exFAT, label `Moku`) di-auto-mount oleh layanan `devmon` ke `/media/devmon/Moku`. Isinya hanya `System Volume Information`. Zona waktu masih `Etc/UTC`.
