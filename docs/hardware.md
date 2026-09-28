# Inventaris hardware STB

Diambil: 2026-09-28 (Fase 0, poin 1), sebelum ada perubahan apa pun di STB.

## Ringkasan

| Hal | Nilai |
|---|---|
| Hostname | `aml-s9xx-box` |
| Kernel | `6.12.35-current-meson64` (aarch64) |
| OS | Armbian_community 25.8.0-trunk.309, basis Ubuntu 24.04 noble |
| RAM | 1,9 GiB total, ~1,5 GiB available saat idle |
| Swap | zram0 960 MiB (lzo-rle) |
| `/var/log` | zram1 50 MiB (log disimpan di RAM, ditulis ke disk berkala oleh Armbian) |
| eMMC | `mmcblk2` 7,3 GB: `p1` 488M vfat `BOOT_EMMC` → `/boot`, `p2` 5,9G ext4 `ROOT_EMMC` → `/` (48% terpakai) |
| microSD | `mmcblk1` 116,1 GB: `p1` exFAT label `Moku`, di-auto-mount oleh `devmon` ke `/media/devmon/Moku` (isi hanya `System Volume Information`) |
| Paket ditahan | `linux-dtb-current-meson64`, `linux-image-current-meson64` |
| Zona waktu | `Etc/UTC` (jam sistem sinkron) |

Catatan: layanan `devmon@devmon.service` aktif dan otomatis memasang media yang dicolok.
Ini relevan untuk poin 4 (format microSD).

## Output mentah

### `uname -a`
```
Linux aml-s9xx-box 6.12.35-current-meson64 #1 SMP PREEMPT Fri Jun 27 10:11:46 UTC 2025 aarch64 aarch64 aarch64 GNU/Linux
```

### `cat /etc/os-release`
```
PRETTY_NAME="Armbian_community 25.8.0-trunk.309 noble"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION="24.04 LTS (Noble Numbat)"
VERSION_CODENAME=noble
ID=ubuntu
ID_LIKE=debian
HOME_URL="https://www.armbian.com"
SUPPORT_URL="https://forum.armbian.com"
BUG_REPORT_URL="https://www.armbian.com/bugs"
PRIVACY_POLICY_URL="https://www.armbian.com"
UBUNTU_CODENAME=noble
LOGO="armbian-logo"
ARMBIAN_PRETTY_NAME="Armbian_community 25.8.0-trunk.309 noble"
```

### `lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL`
```
NAME           SIZE TYPE FSTYPE LABEL     MOUNTPOINT
mmcblk2        7.3G disk
├─mmcblk2p1    488M part vfat   BOOT_EMMC /boot
└─mmcblk2p2    5.9G part ext4   ROOT_EMMC /
mmcblk2boot0     4M disk
mmcblk2boot1     4M disk
mmcblk1      116.1G disk
└─mmcblk1p1  116.1G part exfat  Moku      /media/devmon/Moku
zram0        960.5M disk                  [SWAP]
zram1           50M disk                  /var/log
zram2            0B disk
```

### `df -h`
```
Filesystem      Size  Used Avail Use% Mounted on
tmpfs           193M  8.0M  185M   5% /run
/dev/mmcblk2p2  5.7G  2.8G  3.0G  48% /
tmpfs           961M     0  961M   0% /dev/shm
tmpfs           5.0M     0  5.0M   0% /run/lock
tmpfs           961M     0  961M   0% /tmp
/dev/mmcblk2p1  488M   96M  393M  20% /boot
/dev/zram1       47M  1.5M   42M   4% /var/log
tmpfs           193M  4.0K  193M   1% /run/user/0
/dev/mmcblk1p1  117G  768K  117G   1% /media/devmon/Moku
```

### `free -h`
```
               total        used        free      shared  buff/cache   available
Mem:           1.9Gi       434Mi       903Mi       9.5Mi       668Mi       1.5Gi
Swap:          960Mi          0B       960Mi
```

### `apt-mark showhold`
```
linux-dtb-current-meson64
linux-image-current-meson64
```

### `zramctl`
```
NAME       ALGORITHM DISKSIZE  DATA  COMPR TOTAL STREAMS MOUNTPOINT
/dev/zram1 lzo-rle        50M  1.5M 436.5K  1.8M       4 /var/log
/dev/zram0 lzo-rle     960.5M    4K    74B   12K       4 [SWAP]
```
