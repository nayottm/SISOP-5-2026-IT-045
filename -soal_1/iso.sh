set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSBOOT_DIR="$SCRIPT_DIR/osboot"
ISO_DIR="$SCRIPT_DIR/iso_staging"

echo "[iso.sh] Membuat bootable ISO..."

# ── Cek file yang diperlukan ──────────────────────────────────────────────────
echo "[*] Mengecek file prerequisite..."
MISSING=0
for f in bzImage single.gz multi.gz; do
    if [ ! -f "$OSBOOT_DIR/$f" ]; then
        echo "[✗] File tidak ditemukan: osboot/$f"
        MISSING=1
    else
        echo "[✓] $f ($(du -h "$OSBOOT_DIR/$f" | cut -f1))"
    fi
done
if [ "$MISSING" -eq 1 ]; then
    echo ""
    echo "Jalankan script berikut terlebih dahulu:"
    echo "  ./kernel.sh   -> menghasilkan osboot/bzImage"
    echo "  ./single.sh   -> menghasilkan osboot/single.gz"
    echo "  ./multi.sh    -> menghasilkan osboot/multi.gz"
    exit 1
fi

# ── Install GRUB tools ────────────────────────────────────────────────────────
echo "[*] Install GRUB tools..."
sudo apt-get install -y -qq grub-common grub-pc-bin xorriso mtools

# ── Buat struktur direktori ISO ───────────────────────────────────────────────
echo "[*] Membuat struktur direktori ISO..."
rm -rf "$ISO_DIR"
mkdir -p "$ISO_DIR/boot/grub"

# ── Copy kernel dan filesystem ────────────────────────────────────────────────
echo "[*] Copy kernel dan filesystem..."
cp "$OSBOOT_DIR/bzImage"   "$ISO_DIR/boot/"
cp "$OSBOOT_DIR/single.gz" "$ISO_DIR/boot/"
cp "$OSBOOT_DIR/multi.gz"  "$ISO_DIR/boot/"

# ── GRUB config ───────────────────────────────────────────────────────────────
# ISO harus bisa load KEDUA filesystem (single dan multi) — spec soal poin 5
echo "[*] Membuat grub.cfg..."
cat > "$ISO_DIR/boot/grub/grub.cfg" << 'EOF'
# FarewellOS - GRUB Bootloader Configuration
set timeout=10
set default=0

# Menu tampilan
set color_normal=white/black
set color_highlight=black/white

menuentry "FarewellOS - Single User Mode" {
    echo "Loading FarewellOS kernel..."
    linux /boot/bzImage quiet console=tty0 console=ttyS0,115200
    echo "Loading single-user filesystem..."
    initrd /boot/single.gz
}

menuentry "FarewellOS - Multi User Mode" {
    echo "Loading FarewellOS kernel..."
    linux /boot/bzImage quiet console=tty0 console=ttyS0,115200
    echo "Loading multi-user filesystem..."
    initrd /boot/multi.gz
}

menuentry "FarewellOS - Single User (debug)" {
    linux /boot/bzImage console=tty0 console=ttyS0,115200
    initrd /boot/single.gz
}

menuentry "FarewellOS - Multi User (debug)" {
    linux /boot/bzImage console=tty0 console=ttyS0,115200
    initrd /boot/multi.gz
}
EOF

# ── Build ISO ─────────────────────────────────────────────────────────────────
echo "[*] Membuat ISO dengan grub-mkrescue..."
grub-mkrescue \
    --output="$OSBOOT_DIR/farewell.iso" \
    "$ISO_DIR" \
    2>&1 | grep -v "^$" | tail -5

# ── Verifikasi output ─────────────────────────────────────────────────────────
if [ -f "$OSBOOT_DIR/farewell.iso" ]; then
    echo ""
    echo "[✓] iso.sh selesai!"
    echo "[✓] Output: $OSBOOT_DIR/farewell.iso ($(du -h "$OSBOOT_DIR/farewell.iso" | cut -f1))"
else
    echo "[✗] Gagal membuat ISO."
    exit 1
fi

# ── Cleanup staging ───────────────────────────────────────────────────────────
rm -rf "$ISO_DIR"
echo "[*] Staging directory dibersihkan."
