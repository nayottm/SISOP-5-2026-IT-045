set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSBOOT_DIR="$SCRIPT_DIR/osboot"

echo "[backup.sh] Membuat backup artifact..."

# ── Cek zip ───────────────────────────────────────────────────────────────────
if ! command -v zip &>/dev/null; then
    echo "[*] Install zip..."
    sudo apt-get install -y -qq zip
fi

# ── Generate nama file sesuai format soal: farewell_backup_[DDMMYYYY-HHMMSS] ──
TIMESTAMP=$(date +"%d%m%Y-%H%M%S")
BACKUP_NAME="farewell_backup_${TIMESTAMP}.zip"
BACKUP_PATH="$OSBOOT_DIR/$BACKUP_NAME"

echo "[*] Nama backup: $BACKUP_NAME"
echo ""

# ── Kumpulkan file yang akan dibackup ────────────────────────────────────────
FILES=()
for f in bzImage single.gz multi.gz farewell.iso; do
    if [ -f "$OSBOOT_DIR/$f" ]; then
        FILES+=("$f")
        SIZE=$(du -h "$OSBOOT_DIR/$f" | cut -f1)
        echo "[✓] $f ($SIZE)"
    else
        echo "[!] $f tidak ditemukan, dilewati."
    fi
done

echo ""

if [ ${#FILES[@]} -eq 0 ]; then
    echo "[✗] Tidak ada file untuk dibackup."
    echo "    Jalankan kernel.sh, single.sh, multi.sh, iso.sh terlebih dahulu."
    exit 1
fi

# ── Buat zip ──────────────────────────────────────────────────────────────────
echo "[*] Membuat arsip..."
cd "$OSBOOT_DIR"
zip -9 "$BACKUP_NAME" "${FILES[@]}"
cd "$SCRIPT_DIR"

if [ ! -f "$BACKUP_PATH" ]; then
    echo "[✗] Gagal membuat arsip."
    exit 1
fi

echo ""
echo "[✓] Arsip dibuat: $BACKUP_PATH"
echo "[✓] Ukuran: $(du -h "$BACKUP_PATH" | cut -f1)"
echo ""

# ── Hapus file asli setelah diarsip ──────────────────────────────────────────
echo "[*] Menghapus file asli..."
for f in "${FILES[@]}"; do
    rm -f "$OSBOOT_DIR/$f"
    echo "    Dihapus: $f"
done

echo ""
echo "[✓] backup.sh selesai!"
echo "[✓] File backup: osboot/$BACKUP_NAME"
