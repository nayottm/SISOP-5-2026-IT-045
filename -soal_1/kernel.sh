set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSBOOT_DIR="$SCRIPT_DIR/osboot"
KERNEL_VERSION="6.1.1"
KERNEL_DIR="linux-${KERNEL_VERSION}"
KERNEL_TAR="${KERNEL_DIR}.tar.xz"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/${KERNEL_TAR}"

echo "[kernel.sh] Memulai build kernel Linux ${KERNEL_VERSION}..."

# ── Dependencies ──────────────────────────────────────────────────────────────
echo "[*] Install dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    build-essential bison flex libelf-dev libssl-dev \
    bc libncurses-dev wget xz-utils

mkdir -p "$OSBOOT_DIR"
cd "$SCRIPT_DIR"

# ── Download ──────────────────────────────────────────────────────────────────
if [ ! -f "$KERNEL_TAR" ]; then
    echo "[*] Downloading ${KERNEL_TAR}..."
    wget -q --show-progress "$KERNEL_URL" -O "$KERNEL_TAR"
else
    echo "[*] Tarball sudah ada, skip download."
fi

# ── Extract ───────────────────────────────────────────────────────────────────
if [ ! -d "$KERNEL_DIR" ]; then
    echo "[*] Extracting..."
    tar -xf "$KERNEL_TAR"
else
    echo "[*] Source sudah ada, skip extract."
fi

cd "$KERNEL_DIR"

# ── Configure ─────────────────────────────────────────────────────────────────
if [ -f "$SCRIPT_DIR/.config" ]; then
    echo "[*] Menggunakan .config yang sudah ada..."
    cp "$SCRIPT_DIR/.config" .config
    make olddefconfig
else
    echo "[*] Generate konfigurasi kernel..."
    make tinyconfig

    # 64-bit
    ./scripts/config --enable CONFIG_64BIT

    # General setup
    ./scripts/config --enable CONFIG_PRINTK
    ./scripts/config --enable CONFIG_FUTEX
    ./scripts/config --enable CONFIG_BLK_DEV_INITRD
    ./scripts/config --enable CONFIG_CGROUPS
    ./scripts/config --enable CONFIG_EXPERT

    # Block layer
    ./scripts/config --enable CONFIG_BLOCK
    ./scripts/config --enable CONFIG_BLK_DEV

    # Executable formats
    ./scripts/config --enable CONFIG_BINFMT_ELF
    ./scripts/config --enable CONFIG_BINFMT_SCRIPT

    # TTY / Console
    ./scripts/config --enable CONFIG_TTY
    ./scripts/config --enable CONFIG_VT
    ./scripts/config --enable CONFIG_VT_CONSOLE
    ./scripts/config --enable CONFIG_DUMMY_CONSOLE
    ./scripts/config --enable CONFIG_SERIAL_8250
    ./scripts/config --enable CONFIG_SERIAL_8250_CONSOLE

    # Device drivers
    ./scripts/config --enable CONFIG_DEVTMPFS
    ./scripts/config --enable CONFIG_DEVTMPFS_MOUNT
    ./scripts/config --enable CONFIG_VIRTIO_CONSOLE

    # Network (wajib untuk internet access - poin 8)
    ./scripts/config --enable CONFIG_NET
    ./scripts/config --enable CONFIG_INET
    ./scripts/config --enable CONFIG_UNIX
    ./scripts/config --enable CONFIG_PACKET
    ./scripts/config --enable CONFIG_TCP_CONG_CUBIC
    ./scripts/config --enable CONFIG_NETDEVICES
    ./scripts/config --enable CONFIG_NET_CORE
    ./scripts/config --enable CONFIG_ETHERNET
    ./scripts/config --enable CONFIG_NET_VENDOR_INTEL
    ./scripts/config --enable CONFIG_E1000          # Intel e1000 - dipakai QEMU
    ./scripts/config --enable CONFIG_VIRTIO_NET     # Virtio network
    ./scripts/config --enable CONFIG_IP_PNP         # IP autoconfiguration
    ./scripts/config --enable CONFIG_IP_PNP_DHCP    # DHCP support

    # Crypto (dibutuhkan untuk TLS/wget https)
    ./scripts/config --enable CONFIG_CRYPTO
    ./scripts/config --enable CONFIG_CRYPTO_SHA256
    ./scripts/config --enable CONFIG_CRYPTO_MD5
    ./scripts/config --enable CONFIG_CRYPTO_AES
    ./scripts/config --enable CONFIG_CRYPTO_HMAC
    ./scripts/config --enable CONFIG_CRYPTO_CBC
    ./scripts/config --enable CONFIG_TLS

    # Block devices
    ./scripts/config --enable CONFIG_BLK_DEV_LOOP
    ./scripts/config --enable CONFIG_BLK_DEV_RAM
    ./scripts/config --enable CONFIG_BLK_DEV_SD
    ./scripts/config --enable CONFIG_SCSI
    ./scripts/config --enable CONFIG_SCSI_LOWLEVEL
    ./scripts/config --enable CONFIG_ATA
    ./scripts/config --enable CONFIG_ATA_PIIX
    ./scripts/config --enable CONFIG_VIRTIO_BLK
    ./scripts/config --enable CONFIG_VIRTIO_PCI
    ./scripts/config --enable CONFIG_VIRTIO_MMIO
    ./scripts/config --enable CONFIG_VIRTIO

    # Filesystems
    ./scripts/config --enable CONFIG_EXT4_FS
    ./scripts/config --enable CONFIG_EXT3_FS
    ./scripts/config --enable CONFIG_EXT2_FS
    ./scripts/config --enable CONFIG_PROC_FS
    ./scripts/config --enable CONFIG_SYSFS
    ./scripts/config --enable CONFIG_SYSCTL
    ./scripts/config --enable CONFIG_TMPFS
    ./scripts/config --enable CONFIG_FUSE_FS        # FUSE - dibutuhkan poin 10
    ./scripts/config --enable CONFIG_INOTIFY_USER
    ./scripts/config --enable CONFIG_AUTOFS_FS

    # Networking extras
    ./scripts/config --enable CONFIG_DNS_RESOLVER
    ./scripts/config --enable CONFIG_NETWORK_FILESYSTEMS

    make olddefconfig

    # Simpan .config untuk reuse
    cp .config "$SCRIPT_DIR/.config"
    echo "[*] .config disimpan ke soal_1/.config"
fi

# ── Compile ───────────────────────────────────────────────────────────────────
echo "[*] Compile kernel dengan $(nproc) thread..."
echo "[!] Proses ini memakan waktu 30-60 menit."
make -j"$(nproc)" 2>&1 | tail -n 5

# ── Copy output ───────────────────────────────────────────────────────────────
if [ -f "arch/x86/boot/bzImage" ]; then
    cp arch/x86/boot/bzImage "$OSBOOT_DIR/bzImage"
    echo ""
    echo "[✓] kernel.sh selesai!"
    echo "[✓] Output: $OSBOOT_DIR/bzImage ($(du -h "$OSBOOT_DIR/bzImage" | cut -f1))"
else
    echo "[✗] bzImage tidak ditemukan. Compile gagal."
    exit 1
fi
