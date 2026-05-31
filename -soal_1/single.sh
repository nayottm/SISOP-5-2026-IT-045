#!/bin/bash
# single.sh
# Build single-user root filesystem
# Output: osboot/single.gz
#
# Spec dari soal:
#   User      : root (hanya root)
#   Directory : bin/, dev/, proc/, sys/, etc/, tmp/, root/
#   Access    : root bisa akses apapun

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSBOOT_DIR="$SCRIPT_DIR/osboot"
BUILD_DIR="$SCRIPT_DIR/build_single"

echo "[single.sh] Build single-user filesystem..."

# ── Root check ────────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "[!] Perlu root. Re-run dengan sudo..."
    exec sudo bash "$0" "$@"
fi

# ── Dependencies ──────────────────────────────────────────────────────────────
apt-get install -y -qq busybox-static

mkdir -p "$OSBOOT_DIR"

# ── Bersihkan build sebelumnya ────────────────────────────────────────────────
rm -rf "$BUILD_DIR"

# ── Buat struktur direktori sesuai spec ──────────────────────────────────────
# Spec: bin/, dev/, proc/, sys/, etc/, tmp/, root/
echo "[*] Membuat struktur direktori..."
mkdir -p "$BUILD_DIR"/{bin,dev,proc,sys,etc,tmp,root}
mkdir -p "$BUILD_DIR"/etc/init.d
mkdir -p "$BUILD_DIR"/sbin
mkdir -p "$BUILD_DIR"/usr/bin

# ── Copy device files ─────────────────────────────────────────────────────────
echo "[*] Copy device files..."
cp -a /dev/null    "$BUILD_DIR/dev/"
cp -a /dev/zero    "$BUILD_DIR/dev/"
cp -a /dev/console "$BUILD_DIR/dev/"
for tty in /dev/tty /dev/tty0 /dev/tty1 /dev/ttyS0; do
    [ -e "$tty" ] && cp -a "$tty" "$BUILD_DIR/dev/" 2>/dev/null || true
done

# ── Install BusyBox ───────────────────────────────────────────────────────────
echo "[*] Install BusyBox..."
cp /usr/bin/busybox "$BUILD_DIR/bin/"
cd "$BUILD_DIR/bin"
./busybox --install .
cd "$SCRIPT_DIR"

# Symlink ke sbin
for cmd in halt reboot init; do
    ln -sf /bin/busybox "$BUILD_DIR/sbin/$cmd" 2>/dev/null || true
done

# ── /etc/passwd dan /etc/group minimal ───────────────────────────────────────
cat > "$BUILD_DIR/etc/passwd" << 'EOF'
root::0:0:root:/root:/bin/sh
EOF

cat > "$BUILD_DIR/etc/group" << 'EOF'
root:x:0:root
EOF

# ── /etc/hostname ─────────────────────────────────────────────────────────────
echo "farewell-single" > "$BUILD_DIR/etc/hostname"

# ── /etc/profile ─────────────────────────────────────────────────────────────
cat > "$BUILD_DIR/etc/profile" << 'EOF'
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export PS1='root@farewell-single:~# '
EOF

# ── /tmp permissions ──────────────────────────────────────────────────────────
chmod 1777 "$BUILD_DIR/tmp"

# ── init script ───────────────────────────────────────────────────────────────
# Single user: mount filesystem penting, lalu langsung exec shell sebagai root
echo "[*] Membuat init..."
cat > "$BUILD_DIR/init" << 'EOF'
#!/bin/sh

# Mount filesystem essential
/bin/mount -t proc  none /proc
/bin/mount -t sysfs none /sys
/bin/mount -t devtmpfs none /dev 2>/dev/null || true

# Hostname
/bin/hostname farewell-single

# Permissions
chmod 1777 /tmp

# Environment
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root

echo ""
echo "  FarewellOS - Single User Mode"
echo "  Logged in as: root"
echo ""

# Langsung masuk shell — tidak ada proses login
exec /bin/sh
EOF
chmod +x "$BUILD_DIR/init"

# ── Pack initramfs ────────────────────────────────────────────────────────────
echo "[*] Packing initramfs..."
cd "$BUILD_DIR"
find . | cpio -oH newc 2>/dev/null | gzip -9 > "$OSBOOT_DIR/single.gz"
cd "$SCRIPT_DIR"

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"

echo ""
echo "[✓] single.sh selesai!"
echo "[✓] Output: $OSBOOT_DIR/single.gz ($(du -h "$OSBOOT_DIR/single.gz" | cut -f1))"
