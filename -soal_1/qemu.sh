SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSBOOT_DIR="$SCRIPT_DIR/osboot"

# ── Cek QEMU tersedia ─────────────────────────────────────────────────────────
if ! command -v qemu-system-x86_64 &>/dev/null; then
    echo "[!] qemu-system-x86_64 tidak ditemukan. Install..."
    sudo apt-get install -y -qq qemu-system-x86
fi

# ── Tentukan mode display ─────────────────────────────────────────────────────
# Gunakan curses jika di terminal, fallback ke nographic
if [ -t 1 ]; then
    DISPLAY_OPT="-display curses"
else
    DISPLAY_OPT="-nographic"
fi

# ── Opsi QEMU dasar ───────────────────────────────────────────────────────────
QEMU_BASE="qemu-system-x86_64
    -smp 2
    -m 256
    -vga std
    $DISPLAY_OPT"

# ── Network: user-mode NAT untuk internet access (poin 8) ────────────────────
# -netdev user: QEMU NAT otomatis, guest dapat internet tanpa setup tambahan
# -device e1000: Intel e1000 NIC, dikenali kernel sebagai eth0
QEMU_NET="-netdev user,id=net0 -device e1000,netdev=net0"

# ── Kernel append args ────────────────────────────────────────────────────────
# console=tty0       : output ke VGA
# console=ttyS0,115200 : output ke serial (untuk mode nographic)
KERNEL_ARGS="console=tty0 console=ttyS0,115200"

# ── Proses argumen ────────────────────────────────────────────────────────────
case "$1" in

    --single)
        echo "============================================"
        echo " FarewellOS - Single User Mode"
        echo "============================================"
        for f in bzImage single.gz; do
            if [ ! -f "$OSBOOT_DIR/$f" ]; then
                echo "[✗] File tidak ada: osboot/$f"
                echo "    Jalankan ./kernel.sh dan ./single.sh terlebih dahulu."
                exit 1
            fi
        done
        echo "[*] Booting single-user filesystem..."
        echo "[*] Tekan Ctrl+A X untuk keluar QEMU (mode nographic)"
        echo ""
        $QEMU_BASE \
            $QEMU_NET \
            -kernel "$OSBOOT_DIR/bzImage" \
            -initrd "$OSBOOT_DIR/single.gz" \
            -append "$KERNEL_ARGS"
        ;;

    --multi)
        echo "============================================"
        echo " FarewellOS - Multi User Mode"
        echo "============================================"
        for f in bzImage multi.gz; do
            if [ ! -f "$OSBOOT_DIR/$f" ]; then
                echo "[✗] File tidak ada: osboot/$f"
                echo "    Jalankan ./kernel.sh dan ./multi.sh terlebih dahulu."
                exit 1
            fi
        done
        echo "[*] Booting multi-user filesystem..."
        echo "[*] Login: root/root123, henn/henn123, hann/hann123, viii/viii123, kids/kids123"
        echo "[*] Tekan Ctrl+A X untuk keluar QEMU (mode nographic)"
        echo ""
        $QEMU_BASE \
            $QEMU_NET \
            -kernel "$OSBOOT_DIR/bzImage" \
            -initrd "$OSBOOT_DIR/multi.gz" \
            -append "$KERNEL_ARGS"
        ;;

    --all)
        echo "============================================"
        echo " FarewellOS - ISO Boot (GRUB Menu)"
        echo "============================================"
        if [ ! -f "$OSBOOT_DIR/farewell.iso" ]; then
            echo "[✗] File tidak ada: osboot/farewell.iso"
            echo "    Jalankan ./iso.sh terlebih dahulu."
            exit 1
        fi
        echo "[*] Booting dari farewell.iso..."
        echo "[*] GRUB menu akan muncul — pilih Single atau Multi User Mode"
        echo "[*] Tekan Ctrl+A X untuk keluar QEMU (mode nographic)"
        echo ""
        $QEMU_BASE \
            $QEMU_NET \
            -cdrom "$OSBOOT_DIR/farewell.iso" \
            -boot d
        ;;

    *)
        echo "Usage: $0 [--single | --multi | --all]"
        echo ""
        echo "  --single   Boot langsung ke single-user (kernel + initrd)"
        echo "  --multi    Boot langsung ke multi-user  (kernel + initrd)"
        echo "  --all      Boot dari ISO via GRUB menu (pilih single/multi)"
        echo ""
        echo "Contoh:"
        echo "  ./qemu.sh --single"
        echo "  ./qemu.sh --multi"
        echo "  ./qemu.sh --all"
        exit 1
        ;;
esac
