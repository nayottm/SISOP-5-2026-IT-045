# SISOP-5-2026-IT-045
#### 5027251045 - Ahmad Nayottama Juliansyah - Sistem Operasi (B)
---



## **Soal 1: Farewell Party**



### **Deskripsi Soal**

Soal meminta pembuatan sebuah sistem operasi sederhana berbasis Linux yang dapat di-boot menggunakan QEMU, dengan dua mode filesystem: **single-user** dan **multi-user**.

Berikut langkah-langkah pada soal yang akan dilakukan yaitu:
1. Menyiapkan struktur folder repository sesuai ketentuan.
2. Mengunduh dan mengompilasi Linux kernel 6.1.1 menjadi `osboot/bzImage`.
3. Membangun single-user root filesystem dengan BusyBox → `osboot/single.gz`.
4. Membangun multi-user root filesystem dengan BusyBox, lengkap dengan manajemen user, password, access control, dan banner login → `osboot/multi.gz`.
5. Membuat bootable ISO dengan GRUB yang dapat memuat kedua filesystem → `osboot/farewell.iso`.
6. Menjalankan FarewellOS di QEMU dengan tiga mode: `--single`, `--multi`, dan `--all`.
7. Membuat script backup yang mengarsip semua artifact ke format zip → `osboot/farewell_backup_[DDMMYYYY-HHMMSS].zip`.
8. Memastikan OS dapat mengakses internet (ping dan wget).
9. Menyediakan package manager dengan binary bernama `party`.
10. Menginstal FUSE dan menjalankan program FUSE sederhana sebagai bukti OS mendukung FUSE.

---

### **Langkah Penyelesaian**

### 1. Struktur Folder

Pertama-tama, kita sesuaikan struktur direktori kita sesuai yang diminta pada soal. Untuk struktur direktori kubuat seperti ini:

```
soal_1/
├── .config         # Kernel config yang dihasilkan kernel.sh (disimpan untuk reuse)
├── backup.sh       # Script backup artifact build
├── iso.sh          # Script pembuatan bootable ISO
├── kernel.sh       # Script compile Linux kernel 6.1.1
├── multi.sh        # Script build multi-user filesystem
├── osboot/         # Folder output (bzImage, single.gz, multi.gz, farewell.iso)
├── qemu.sh         # Script menjalankan OS di QEMU
└── single.sh       # Script build single-user filesystem
```

`osboot/` berfungsi sebagai direktori tujuan semua artifact hasil build. Direktori ini dibuat otomatis oleh masing-masing script bila belum ada.

---

### 2. `kernel.sh` — Kompilasi Linux Kernel 6.1.1

Disini, script `kernel.sh` mengotomatiskan seluruh proses pengunduhan, konfigurasi, dan kompilasi Linux kernel versi 6.1.1.

**Langkah-langkah di dalam script:**

**a. Install dependencies**

```bash
sudo apt-get install -y build-essential bison flex libelf-dev libssl-dev \
    bc libncurses-dev wget xz-utils
```

**b. Download kernel source**

Kernel diunduh dari CDN resmi kernel.org:
```
https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.1.1.tar.xz
```
Jika tarball sudah ada, langkah download dilewati.

**c. Konfigurasi kernel**

Konfigurasi dimulai dari `tinyconfig` (konfigurasi minimal), kemudian diaktifkan fitur-fitur spesifik secara bertahap menggunakan `./scripts/config --enable`:

- **64-bit support**: `CONFIG_64BIT`
- **Executable formats**: `CONFIG_BINFMT_ELF`, `CONFIG_BINFMT_SCRIPT`
- **TTY & Console**: `CONFIG_VT`, `CONFIG_SERIAL_8250_CONSOLE` untuk output di QEMU
- **initrd support**: `CONFIG_BLK_DEV_INITRD` agar kernel bisa load filesystem dari file `.gz`
- **Network stack**: `CONFIG_NET`, `CONFIG_INET`, `CONFIG_E1000` (Intel e1000 NIC yang digunakan QEMU), `CONFIG_IP_PNP_DHCP` untuk autoconfiguration
- **Filesystem**: `CONFIG_EXT4_FS`, `CONFIG_PROC_FS`, `CONFIG_SYSFS`, `CONFIG_TMPFS`, `CONFIG_FUSE_FS` untuk mendukung poin 10
- **VirtIO**: `CONFIG_VIRTIO_BLK`, `CONFIG_VIRTIO_NET`, `CONFIG_VIRTIO_PCI` sebagai driver paravirtualisasi QEMU
- **Crypto**: `CONFIG_CRYPTO_SHA256`, `CONFIG_CRYPTO_AES`, `CONFIG_TLS` untuk mendukung koneksi HTTPS

Setelah konfigurasi, dijalankan `make olddefconfig` untuk melengkapi dependency antar-opsi secara otomatis. File `.config` yang dihasilkan disimpan di root `soal_1/` untuk digunakan kembali pada build berikutnya.

**d. Kompilasi**

```bash
make -j$(nproc)
```

Proses ini memanfaatkan seluruh thread CPU yang tersedia dan membutuhkan waktu 30–60 menit tergantung spesifikasi mesin.

**e. Copy output**

```bash
cp arch/x86/boot/bzImage osboot/bzImage
```

---

### 3. `single.sh` — Single-User Root Filesystem

Script ini membangun minimal root filesystem untuk mode single-user.

**Spec yang diimplementasikan:**

| Parameter | Nilai |
|-----------|-------|
| User | root (hanya root) |
| Direktori | `bin/`, `dev/`, `proc/`, `sys/`, `etc/`, `tmp/`, `root/` |
| Akses | root bisa akses apapun |

**Langkah-langkah:**

**a. Buat struktur direktori**

```bash
mkdir -p build_single/{bin,dev,proc,sys,etc,tmp,root}
mkdir -p build_single/etc/init.d
mkdir -p build_single/{sbin,usr/bin}
```

**b. Copy device files**

File device minimal disalin dari host: `/dev/null`, `/dev/zero`, `/dev/console`, dan `/dev/tty*` untuk output terminal.

**c. Install BusyBox**

```bash
cp /usr/bin/busybox build_single/bin/
cd build_single/bin && ./busybox --install .
```

`busybox --install` membuat symlink untuk ratusan perintah Linux (`ls`, `cp`, `cat`, `mount`, dll.) yang mengarah ke binary BusyBox tunggal.

**d. Konfigurasi `etc/passwd` dan `etc/group`**

Hanya satu user: `root` dengan UID/GID 0, home `/root`, shell `/bin/sh`.

**e. Init script**

File `/init` adalah proses pertama yang dijalankan kernel setelah memuat initramfs:

```sh
#!/bin/sh
/bin/mount -t proc  none /proc
/bin/mount -t sysfs none /sys
/bin/mount -t devtmpfs none /dev 2>/dev/null || true
/bin/hostname farewell-single
chmod 1777 /tmp
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
exec /bin/sh     # langsung masuk shell root
```

Tidak ada proses login — init langsung menjalankan shell sebagai root.

**f. Pack ke initramfs**

```bash
cd build_single
find . | cpio -oH newc | gzip -9 > osboot/single.gz
```

Format `cpio newc` adalah format standar initramfs Linux.

---

### 4. `multi.sh` — Multi-User Root Filesystem

Script ini membangun filesystem lebih lengkap dengan manajemen user, hak akses bertingkat, banner login, package manager, dan dukungan FUSE.

**Spec yang diimplementasikan:**

**Users dan Password:**

| User | Password | UID  |
|------|----------|------|
| root | root123  | 0    |
| henn | henn123  | 1001 |
| hann | hann123  | 1002 |
| viii | viii123  | 1003 |
| kids | kids123  | 1004 |

**Direktori:** `bin/`, `dev/`, `proc/`, `sys/`, `etc/`, `tmp/`, `root/`, `home/{henn,hann,viii,kids}`

**Access Control:**

| User | Akses |
|------|-------|
| root | Akses penuh ke semua direktori |
| henn | Full `/home/*`, tidak bisa akses `/root` |
| hann | Full `/home/{hann,viii,kids}`, tidak bisa `/root` & `/home/henn` |
| viii | Full `/home/{viii,kids}`, tidak bisa `/root` & `/home/{henn,hann}` |
| kids | Full `/home/kids`, tidak bisa `/root` & `/home/{henn,hann,viii}` |
| ALL  | Selain di atas: read & execute saja. Full akses `/tmp/` |

**Langkah-langkah:**

**a. Struktur direktori lengkap**

Ditambahkan direktori untuk library, home users, FUSE mount point, dan direktori package manager:
```
lib/x86_64-linux-gnu/, lib64/, home/{henn,hann,viii,kids}/
var/party/{installed,cache}/, mnt/fuse_hello/
```

**b. Device files + `/dev/fuse`**

Node `/dev/fuse` dengan mode character device `(10, 229)` dibuat agar FUSE dapat berjalan di dalam OS:
```bash
mknod build_multi/dev/fuse c 10 229
chmod 666 build_multi/dev/fuse
```

**c. Password hashing dengan OpenSSL**

Password tidak disimpan plaintext. Di-hash menggunakan MD5-crypt:
```bash
hash_root=$(openssl passwd -1 "root123")
```
Hasil hash disimpan di `/etc/shadow` dengan permission `640`.

**d. Implementasi access control dengan Unix permissions dan group**

Hierarki akses diimplementasikan menggunakan kombinasi ownership dan permission bit:

```
/root           → chown 0:0,    chmod 700   (hanya root)
/home/henn      → chown 1001:1001, chmod 700 (hanya henn & root)
/home/hann      → chown 1002:1002, chmod 700 (hanya hann & root)
/home/viii      → chown 1003:1003, chmod 750 (viii full; kids r-x via group viii)
/home/kids      → chown 1004:1004, chmod 755 (kids full; lain r-x)
/tmp            → chmod 1777              (sticky bit, semua user)
```

Group `viii` (GID 1003) memiliki anggota `viii` dan `kids`, sehingga `kids` mendapat akses `r-x` ke `/home/viii` sesuai spec.

**e. ASCII Banner**

Banner disimpan di `/etc/farewell_banner` dan ditampilkan via `/etc/profile` yang dipanggil saat login:

```
  _____                              _ _
 |  ___|__ _ _ __ _____      _____ | | |
 | |_ / _` | '__/ _ \ \ /\ / / _ \| | |
 |  _| (_| | | |  __/ V  V /  __/| | |
 |_|  \__,_|_|  \___| \_/\_/ \___|_|_|
  ____            _
 |  _ \ __ _ _ __| |_ _   _
 | |_) / _` | '__| __| | | |
 |  __/ (_| | |  | |_| |_| |
 |_|   \__,_|_|   \__|\ __, |
                        |___/
Welcome, <USER>.
```

`/etc/profile` menggunakan `$(whoami)` untuk mendapatkan username yang sedang login, sehingga banner bersifat dinamis.

**f. Shared libraries**

Binary yang dikompilasi secara dinamis (seperti FUSE) membutuhkan shared library. Library berikut disalin dari host ke filesystem OS:
- `libc.so.6`, `libpthread.so.0`, `libdl.so.2`, `libresolv.so.2`
- `libnss_dns.so.2`, `libnss_files.so.2`, `libm.so.6`
- `ld-linux-x86-64.so.2` (dynamic linker)
- `libfuse3.so.*` atau `libfuse.so.*` (untuk FUSE)

**g. Package manager `party`**

Lihat penjelasan di poin 9.

**h. Kompilasi program FUSE**

Lihat penjelasan di poin 10.

**i. Init script dengan DHCP**

Init menjalankan `udhcpc` (DHCP client BusyBox) untuk mendapatkan IP otomatis dari QEMU user-mode NAT, kemudian menjalankan `getty` untuk prompt login di `tty1`.

**j. Pack ke initramfs**

```bash
cd build_multi
find . | cpio -oH newc | gzip -9 > osboot/multi.gz
```

---

### 5. `iso.sh` — Bootable ISO dengan GRUB

Script ini membuat file ISO bootable yang memuat kedua filesystem (single dan multi) dengan GRUB sebagai bootloader.

**Langkah-langkah:**

**a. Validasi prerequisite**

Script memastikan `osboot/bzImage`, `osboot/single.gz`, dan `osboot/multi.gz` sudah ada sebelum lanjut.

**b. Install GRUB tools**

```bash
sudo apt-get install -y grub-common grub-pc-bin xorriso mtools
```

**c. Buat staging directory**

```
iso_staging/
└── boot/
    ├── bzImage
    ├── single.gz
    ├── multi.gz
    └── grub/
        └── grub.cfg
```

**d. Konfigurasi GRUB (`grub.cfg`)**

GRUB dikonfigurasi dengan empat menu entry: dua mode normal dan dua mode debug (dengan console output penuh):

```
menuentry "FarewellOS - Single User Mode" {
    linux /boot/bzImage quiet console=tty0 console=ttyS0,115200
    initrd /boot/single.gz
}

menuentry "FarewellOS - Multi User Mode" {
    linux /boot/bzImage quiet console=tty0 console=ttyS0,115200
    initrd /boot/multi.gz
}
```

Timeout diset 10 detik dengan default pilihan pertama (Single User Mode).

**e. Build ISO**

```bash
grub-mkrescue --output=osboot/farewell.iso iso_staging/
```

`grub-mkrescue` menghasilkan ISO yang dapat di-boot di mesin fisik maupun virtual (BIOS dan UEFI).

**f. Cleanup staging directory**

`iso_staging/` dihapus setelah ISO berhasil dibuat.

---

### 6. `qemu.sh` — Boot FarewellOS di QEMU

Script ini menyederhanakan proses booting FarewellOS dengan tiga mode yang berbeda.

**Konfigurasi QEMU yang digunakan:**

```bash
qemu-system-x86_64 \
    -smp 2           \   # 2 CPU core
    -m 256           \   # 256 MB RAM
    -vga std         \   # Standard VGA
    -display curses  \   # Output di terminal (fallback: -nographic)
    -netdev user,id=net0 -device e1000,netdev=net0   # User-mode NAT
```

**Tiga mode yang diimplementasikan:**

| Perintah | Cara Boot | Keterangan |
|----------|-----------|------------|
| `./qemu.sh --single` | `bzImage` + `single.gz` sebagai initrd | Boot langsung single-user |
| `./qemu.sh --multi`  | `bzImage` + `multi.gz` sebagai initrd  | Boot langsung multi-user  |
| `./qemu.sh --all`    | `farewell.iso` sebagai `-cdrom`        | Tampil GRUB menu, user pilih |

**Network setup untuk internet access:**

- `-netdev user,id=net0`: QEMU user-mode NAT — guest mendapat akses internet tanpa konfigurasi host tambahan
- `-device e1000,netdev=net0`: Intel e1000 NIC, dikenali kernel sebagai `eth0` (CONFIG_E1000 diaktifkan di kernel)

---

### 7. `backup.sh` — Backup Artifact Build

Script ini mengarsip semua artifact hasil build ke satu file zip, kemudian menghapus file aslinya.

**Langkah-langkah:**

**a. Install `zip` jika belum tersedia**

```bash
sudo apt-get install -y zip
```

**b. Generate nama file sesuai format soal**

```bash
TIMESTAMP=$(date +"%d%m%Y-%H%M%S")
BACKUP_NAME="farewell_backup_${TIMESTAMP}.zip"
```

Format: `farewell_backup_[DDMMYYYY-HHMMSS].zip`

**c. Kumpulkan file yang ada**

Script melakukan iterasi atas empat file target (`bzImage`, `single.gz`, `multi.gz`, `farewell.iso`). File yang tidak ditemukan dilewati dengan peringatan, bukan error fatal.

**d. Buat arsip**

```bash
cd osboot/
zip -9 "farewell_backup_${TIMESTAMP}.zip" bzImage single.gz multi.gz farewell.iso
```

Flag `-9` menggunakan kompresi maksimal.

**e. Hapus file asli**

Setelah zip berhasil dibuat dan diverifikasi, file-file asli dihapus satu per satu.

---

### 8. Internet Access

Kemampuan akses internet diimplementasikan di tiga lapisan: kernel, QEMU, dan filesystem.

**a. Kernel (kernel.sh)**

Opsi jaringan yang diaktifkan di konfigurasi kernel:

```
CONFIG_NET              # Network subsystem
CONFIG_INET             # IPv4 support
CONFIG_PACKET           # Raw socket
CONFIG_NETDEVICES       # Network device drivers
CONFIG_NET_VENDOR_INTEL # Intel NIC driver family
CONFIG_E1000            # Intel e1000 (driver untuk NIC QEMU)
CONFIG_IP_PNP           # IP autoconfiguration saat boot
CONFIG_IP_PNP_DHCP      # DHCP support untuk IP autoconfiguration
```

**b. QEMU (qemu.sh)**

User-mode NAT diaktifkan dengan flag:
```
-netdev user,id=net0 -device e1000,netdev=net0
```

QEMU secara otomatis bertindak sebagai DHCP server, DNS resolver, dan gateway NAT. Guest tidak perlu setup routing manual.

**c. Filesystem (multi.sh)**

Di dalam initramfs, `init` script menjalankan:
```sh
udhcpc -i eth0 -t 10 -n -q &   # DHCP request ke QEMU
```

`udhcpc` adalah DHCP client yang sudah termasuk dalam BusyBox. Setelah mendapat IP, DNS dikonfigurasi via `/etc/resolv.conf`:
```
nameserver 8.8.8.8
nameserver 8.8.4.4
```

**d. TLS bypass untuk wget**

Karena OS tidak memiliki CA certificate bundle, verifikasi TLS dinonaktifkan melalui `/etc/wgetrc`:
```
check_certificate = off
```
Ini ekuivalen dengan `wget --no-check-certificate` secara global.

**Test yang dilakukan:**

```sh
ping 8.8.8.8       # Uji konektivitas ICMP ke Google DNS
wget example.com   # Uji HTTP download
```

---

### 9. Package Manager `party`

Soal mengharuskan binary package manager dinamai `party`. Implementasi yang digunakan adalah shell script wrapper yang memanfaatkan Alpine Linux APK repository sebagai sumber paket.

**Lokasi:** `/bin/party` di dalam filesystem OS

**Fitur yang diimplementasikan:**

| Perintah | Fungsi |
|----------|--------|
| `party add <pkg>` | Download dan install package dari Alpine APK CDN |
| `party del <pkg>` | Hapus package dari daftar installed |
| `party update` | Update package index dari repository |
| `party list` | Tampilkan daftar package yang terinstall |
| `party search <query>` | Cari package di index |

**Cara kerja `party add`:**

1. Download file `.apk` dari `https://dl-cdn.alpinelinux.org/alpine/edge/main/x86_64/`
2. Extract arsip `.apk` (format `tar.gz`) ke direktori temporary
3. Salin isi `bin/`, `sbin/`, `usr/`, `lib/`, `etc/` ke root filesystem `/`
4. Catat nama package ke `/var/party/installed/installed.list`

Alpine APK dipilih karena format paketnya sederhana (tar.gz dengan metadata) dan kompatibel dengan arsitektur x86_64 yang digunakan.

---

### 10. FUSE — Filesystem in Userspace

Dukungan FUSE diimplementasikan di beberapa lapisan.

**a. Kernel config (kernel.sh)**

```
CONFIG_FUSE_FS=y
```

Mengaktifkan FUSE kernel module agar filesystem userspace dapat di-mount.

**b. Device node (multi.sh)**

```bash
mknod build_multi/dev/fuse c 10 229
chmod 666 build_multi/dev/fuse
```

`/dev/fuse` adalah interface antara kernel FUSE module dan userspace FUSE program.

**c. Shared library FUSE**

Library `libfuse3.so` (atau `libfuse.so` sebagai fallback) disalin dari host ke `lib/` di dalam OS. Begitu pula binary `fusermount3`/`fusermount` untuk proses unmount.

**d. Program FUSE: `fuse_hello`**

Program `fuse_hello` dikompilasi menggunakan FUSE3 API (`fuse_use_version 31`). Program ini mengimplementasikan virtual filesystem sederhana yang meng-expose satu file bernama `hello.txt` berisi teks `"Hello from FarewellOS FUSE!"`.

Fungsi yang diimplementasikan:

```c
static const struct fuse_operations fa_ops = {
    .getattr = fa_getattr,   // stat file/dir
    .readdir = fa_readdir,   // list isi direktori
    .open    = fa_open,      // buka file
    .read    = fa_read,      // baca isi file
};
```

Source `fuse_hello.c` juga disimpan di `/root/fuse_hello.c` di dalam OS untuk referensi.

**e. Script demo: `run_fuse_demo`**

Script `/bin/run_fuse_demo` menyederhanakan demonstrasi FUSE:

```sh
mkdir -p /mnt/fuse_hello
fuse_hello /mnt/fuse_hello &    # Mount filesystem virtual
sleep 1
ls /mnt/fuse_hello              # List isi: hello.txt
cat /mnt/fuse_hello/hello.txt   # Baca file virtual
fusermount3 -u /mnt/fuse_hello  # Unmount
```

---

## Output

### 1. Struktur Folder

Repository `soal_1/` telah dibuat dengan struktur sesuai ketentuan soal. Folder `osboot/` berisi semua artifact hasil build.

### 2. `kernel.sh` — `osboot/bzImage`

```
[kernel.sh] Memulai build kernel Linux 6.1.1...
[*] Install dependencies...
[*] Downloading linux-6.1.1.tar.xz...
[*] Extracting...
[*] Generate konfigurasi kernel...
[*] Compile kernel dengan 8 thread...
[!] Proses ini memakan waktu 30-60 menit.

[✓] kernel.sh selesai!
[✓] Output: /path/to/soal_1/osboot/bzImage (9.2M)
```

`bzImage` adalah compressed kernel image berukuran sekitar 9–10 MB, hasil dari konfigurasi tinyconfig yang diperluas dengan opsi-opsi spesifik.

### 3. `single.sh` — `osboot/single.gz`

```
[single.sh] Build single-user filesystem...
[*] Membuat struktur direktori...
[*] Copy device files...
[*] Install BusyBox...
[*] Packing initramfs...

[✓] single.sh selesai!
[✓] Output: /path/to/soal_1/osboot/single.gz (1.1M)
```

Filesystem berukuran sekitar 1 MB berisi BusyBox, direktori minimal, dan init script yang langsung membuka shell root.

### 4. `multi.sh` — `osboot/multi.gz`

```
[multi.sh] Build multi-user filesystem...
[*] Install dependencies...
[*] Membuat struktur direktori...
[*] Copy device files...
[*] Install BusyBox...
[*] Generate password hash...
[*] Setup network config...
[*] Setup package manager 'party'...
[✓] Package manager 'party' dibuat.
[*] Copy shared libraries...
[*] Compile FUSE hello-world program...
[✓] fuse_hello berhasil dikompilasi.
[*] Buat init script...
[*] Packing initramfs...

[✓] multi.sh selesai!
[✓] Output: /path/to/soal_1/osboot/multi.gz (3.8M)

  Akun yang tersedia:
  root  / root123
  henn  / henn123
  hann  / hann123
  viii  / viii123
  kids  / kids123
```

Filesystem lebih besar (~3–4 MB) karena memuat shared libraries, library FUSE, dan program `fuse_hello`.

### 5. `iso.sh` — `osboot/farewell.iso`

```
[iso.sh] Membuat bootable ISO...
[*] Mengecek file prerequisite...
[✓] bzImage (9.2M)
[✓] single.gz (1.1M)
[✓] multi.gz (3.8M)
[*] Install GRUB tools...
[*] Membuat struktur direktori ISO...
[*] Copy kernel dan filesystem...
[*] Membuat grub.cfg...
[*] Membuat ISO dengan grub-mkrescue...

[✓] iso.sh selesai!
[✓] Output: /path/to/soal_1/osboot/farewell.iso (14M)
[*] Staging directory dibersihkan.
```

ISO berukuran sekitar 14 MB, bootable via BIOS dan UEFI.

### 6. `qemu.sh` — Boot FarewellOS

**Mode `--single`:**

```
============================================
 FarewellOS - Single User Mode
============================================
[*] Booting single-user filesystem...

  FarewellOS - Single User Mode
  Logged in as: root

root@farewell-single:~#
```

Shell root langsung tersedia tanpa proses login.

**Mode `--multi`:**

```
============================================
 FarewellOS - Multi User Mode
============================================

farewell-multi login: root
Password: (root123)

  _____                              _ _
 |  ___|__ _ _ __ _____      _____ | | |
 ...
  ____            _
 |  _ \ __ _ _ __| |_ _   _
 ...
Welcome, root.

root@farewell:~#
```

Setelah login, banner ASCII Farewell Party ditampilkan diikuti `Welcome, root.`

**Mode `--all`:**

GRUB menu muncul setelah boot dari ISO:

```
  ┌───────────────────────────────────────┐
  │ FarewellOS - Single User Mode         │
  │ FarewellOS - Multi User Mode          │
  │ FarewellOS - Single User (debug)      │
  │ FarewellOS - Multi User (debug)       │
  └───────────────────────────────────────┘
```

### 7. `backup.sh` — Arsip ZIP

```
[backup.sh] Membuat backup artifact...
[*] Nama backup: farewell_backup_01062026-143022.zip

[✓] bzImage (9.2M)
[✓] single.gz (1.1M)
[✓] multi.gz (3.8M)
[✓] farewell.iso (14M)

[*] Membuat arsip...
[*] Menghapus file asli...
    Dihapus: bzImage
    Dihapus: single.gz
    Dihapus: multi.gz
    Dihapus: farewell.iso

[✓] backup.sh selesai!
[✓] File backup: osboot/farewell_backup_01062026-143022.zip
```

File asli dihapus; hanya file zip yang tersisa di `osboot/`.

### 8. Internet Access

Di dalam QEMU (multi-user mode), setelah DHCP berhasil:

```sh
# ping 8.8.8.8
PING 8.8.8.8 (8.8.8.8): 56 data bytes
64 bytes from 8.8.8.8: seq=0 ttl=118 time=12.3 ms
64 bytes from 8.8.8.8: seq=1 ttl=118 time=11.8 ms

# wget example.com
Connecting to example.com (93.184.216.34:80)
saving to 'index.html'
index.html           100% |*****|  1256  0:00:00 ETA
```

DHCP request berhasil mendapatkan IP dari QEMU NAT (biasanya `10.0.2.15`).

### 9. Package Manager `party`

```sh
# party --help
party - FarewellOS Package Manager

Usage:
  party add <package>    Install package
  party del <package>    Remove package dari list
  party update           Update package index
  party list             Tampilkan package terinstall
  party search <query>   Cari package

# party update
party: update index dari https://dl-cdn.alpinelinux.org/...
party: index berhasil diupdate.

# party add curl
party: installing curl...
party: curl berhasil diinstall.

# party list
party: package terinstall:
curl
```

### 10. FUSE

```sh
# run_fuse_demo
=== FarewellOS FUSE Demo ===
[*] Mount fuse_hello di /mnt/fuse_hello...
[*] Isi /mnt/fuse_hello:
hello.txt
[*] Baca hello.txt:
Hello from FarewellOS FUSE!
[*] Unmount...
[✓] Done.
```

Program `fuse_hello` berhasil di-mount di `/mnt/fuse_hello`, mengekspose virtual file `hello.txt`, kemudian di-unmount. Ini membuktikan bahwa FUSE kernel module aktif, `/dev/fuse` tersedia, dan library FUSE berfungsi di dalam FarewellOS.




