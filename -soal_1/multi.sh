set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSBOOT_DIR="$SCRIPT_DIR/osboot"
BUILD_DIR="$SCRIPT_DIR/build_multi"

echo "[multi.sh] Build multi-user filesystem..."

# ── Root check ────────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "[!] Perlu root. Re-run dengan sudo..."
    exec sudo bash "$0" "$@"
fi

# ── Dependencies ──────────────────────────────────────────────────────────────
echo "[*] Install dependencies..."
apt-get install -y -qq busybox-static openssl gcc libfuse3-dev fuse3 2>/dev/null || \
apt-get install -y -qq busybox-static openssl gcc libfuse-dev fuse 2>/dev/null || \
apt-get install -y -qq busybox-static openssl gcc

mkdir -p "$OSBOOT_DIR"

# ── Bersihkan build sebelumnya ────────────────────────────────────────────────
rm -rf "$BUILD_DIR"

# ── Struktur direktori sesuai spec ────────────────────────────────────────────
echo "[*] Membuat struktur direktori..."
mkdir -p "$BUILD_DIR"/{bin,sbin,dev,proc,sys,etc,tmp,root,lib,usr/bin,usr/sbin}
mkdir -p "$BUILD_DIR"/lib/x86_64-linux-gnu
mkdir -p "$BUILD_DIR"/lib64
mkdir -p "$BUILD_DIR"/home/{henn,hann,viii,kids}
mkdir -p "$BUILD_DIR"/etc/init.d
mkdir -p "$BUILD_DIR"/var/{log,run,party/installed,party/cache}
mkdir -p "$BUILD_DIR"/mnt/fuse_hello

# ── Device files ──────────────────────────────────────────────────────────────
echo "[*] Copy device files..."
cp -a /dev/null    "$BUILD_DIR/dev/"
cp -a /dev/zero    "$BUILD_DIR/dev/"
cp -a /dev/console "$BUILD_DIR/dev/"
for tty in /dev/tty /dev/tty0 /dev/tty1 /dev/tty2 /dev/ttyS0; do
    [ -e "$tty" ] && cp -a "$tty" "$BUILD_DIR/dev/" 2>/dev/null || true
done
# /dev/fuse untuk FUSE filesystem (poin 10)
mknod "$BUILD_DIR/dev/fuse" c 10 229 2>/dev/null || true
chmod 666 "$BUILD_DIR/dev/fuse"

# ── BusyBox ───────────────────────────────────────────────────────────────────
echo "[*] Install BusyBox..."
cp /usr/bin/busybox "$BUILD_DIR/bin/"
cd "$BUILD_DIR/bin"
./busybox --install .
cd "$SCRIPT_DIR"

ln -sf /bin/busybox "$BUILD_DIR/usr/bin/busybox" 2>/dev/null || true
for cmd in halt reboot init getty login; do
    ln -sf /bin/busybox "$BUILD_DIR/sbin/$cmd" 2>/dev/null || true
done

# ── Generate password hash ────────────────────────────────────────────────────
echo "[*] Generate password hash..."
hash_root=$(openssl passwd -1 "root123")
hash_henn=$(openssl passwd -1 "henn123")
hash_hann=$(openssl passwd -1 "hann123")
hash_viii=$(openssl passwd -1 "viii123")
hash_kids=$(openssl passwd -1 "kids123")

# ── /etc/passwd ───────────────────────────────────────────────────────────────
cat > "$BUILD_DIR/etc/passwd" << EOF
root:x:0:0:root:/root:/bin/sh
henn:x:1001:1001:henn:/home/henn:/bin/sh
hann:x:1002:1002:hann:/home/hann:/bin/sh
viii:x:1003:1003:viii:/home/viii:/bin/sh
kids:x:1004:1004:kids:/home/kids:/bin/sh
EOF

# ── /etc/shadow ───────────────────────────────────────────────────────────────
cat > "$BUILD_DIR/etc/shadow" << EOF
root:${hash_root}:19000:0:99999:7:::
henn:${hash_henn}:19000:0:99999:7:::
hann:${hash_hann}:19000:0:99999:7:::
viii:${hash_viii}:19000:0:99999:7:::
kids:${hash_kids}:19000:0:99999:7:::
EOF
chmod 640 "$BUILD_DIR/etc/shadow"

# ── /etc/group ────────────────────────────────────────────────────────────────
# Grup dirancang untuk implement access control spec:
# - group 'family'  : semua user (1001-1004) — untuk /tmp full access
# - group per-user  : untuk home dir masing-masing
cat > "$BUILD_DIR/etc/group" << 'EOF'
root:x:0:root
bin:x:1:root
sys:x:2:root
tty:x:5:root,henn,hann,viii,kids
disk:x:6:root
wheel:x:10:root
users:x:100:henn,hann,viii,kids
family:x:200:henn,hann,viii,kids
henn:x:1001:henn
hann:x:1002:hann,viii,kids
viii:x:1003:viii,kids
kids:x:1004:kids
EOF

# ── Permissions sesuai access spec ────────────────────────────────────────────
# root: 700 (hanya root)
chown 0:0    "$BUILD_DIR/root"
chmod 700    "$BUILD_DIR/root"

# /home/henn : 700 (hanya henn & root)
#   henn : full, semua orang lain gabisa
chown 1001:1001 "$BUILD_DIR/home/henn"
chmod 700       "$BUILD_DIR/home/henn"

# /home/hann : group=hann (1002), mode 750
#   hann full, viii & kids gabisa (bukan member group hann)
#   henn gabisa (bukan member group hann)
chown 1002:1002 "$BUILD_DIR/home/hann"
chmod 700       "$BUILD_DIR/home/hann"

# /home/viii : group=viii (1003), viii full, kids juga member group 1003
#   kids bisa baca (r-x) tapi tidak write
#   henn & hann gabisa
chown 1003:1003 "$BUILD_DIR/home/viii"
chmod 750       "$BUILD_DIR/home/viii"
# kids adalah member group viii, jadi bisa r-x

# /home/kids : 755 — kids full, semua bisa read/execute saja
#   tapi owner kids, jadi hanya kids yang bisa write
chown 1004:1004 "$BUILD_DIR/home/kids"
chmod 755       "$BUILD_DIR/home/kids"

# /tmp : full access semua user
chmod 1777 "$BUILD_DIR/tmp"

echo "[*] Permissions set sesuai spec."

# ── ASCII Banner ──────────────────────────────────────────────────────────────
# Spec: ASCII art "Farewell Party" + "Welcome, <USER>."
cat > "$BUILD_DIR/etc/farewell_banner" << 'BANNER'
  _____                              _ _
 |  ___|_ _ _ __ _____      _____ | | |
 | |_ / _` | '__/ _ \ \ /\ / / _ \| | |
 |  _| (_| | | |  __/\ V  V /  __/| | |
 |_|  \__,_|_|  \___| \_/\_/ \___|_|_|
  ____            _
 |  _ \ __ _ _ __| |_ _   _
 | |_) / _` | '__| __| | | |
 |  __/ (_| | |  | |_| |_| |
 |_|   \__,_|_|   \__|\__, |
                       |___/
BANNER

# ── /etc/profile (global, dipanggil saat login) ───────────────────────────────
cat > "$BUILD_DIR/etc/profile" << 'EOF'
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=$(grep "^$(whoami):" /etc/passwd | cut -d: -f6)
export PS1='\u@farewell:\w$ '

# Tampilkan banner saat pertama login
if [ -f /etc/farewell_banner ]; then
    cat /etc/farewell_banner
    echo ""
    echo "Welcome, $(whoami)."
    echo ""
fi
EOF

# ── .profile per user (memanggil /etc/profile) ───────────────────────────────
for user in root henn hann viii kids; do
    if [ "$user" = "root" ]; then
        homedir="/root"
    else
        homedir="/home/$user"
    fi

    cat > "$BUILD_DIR${homedir}/.profile" << PROF
#!/bin/sh
. /etc/profile
PROF
done

# Set ownership .profile masing-masing user
chown 0:0       "$BUILD_DIR/root/.profile"
chown 1001:1001 "$BUILD_DIR/home/henn/.profile"
chown 1002:1002 "$BUILD_DIR/home/hann/.profile"
chown 1003:1003 "$BUILD_DIR/home/viii/.profile"
chown 1004:1004 "$BUILD_DIR/home/kids/.profile"

# ── /etc/hostname ─────────────────────────────────────────────────────────────
echo "farewell-multi" > "$BUILD_DIR/etc/hostname"

# ── /etc/securetty ────────────────────────────────────────────────────────────
cat > "$BUILD_DIR/etc/securetty" << 'EOF'
console
tty1
tty2
ttyS0
EOF

# ── /etc/nsswitch.conf ────────────────────────────────────────────────────────
cat > "$BUILD_DIR/etc/nsswitch.conf" << 'EOF'
passwd:   files
group:    files
shadow:   files
hosts:    files dns
EOF

# ── Network config (poin 8) ───────────────────────────────────────────────────
echo "[*] Setup network config..."
mkdir -p "$BUILD_DIR/etc/network"

cat > "$BUILD_DIR/etc/resolv.conf" << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

cat > "$BUILD_DIR/etc/hosts" << 'EOF'
127.0.0.1   localhost farewell-multi
::1         localhost
EOF

# wget tanpa certificate verification untuk environment tanpa CA bundle
cat > "$BUILD_DIR/etc/wgetrc" << 'EOF'
check_certificate = off
EOF

# ── Package manager 'party' (poin 8) ─────────────────────────────────────────
echo "[*] Setup package manager 'party'..."
cat > "$BUILD_DIR/bin/party" << 'PARTY'
#!/bin/sh
# party - FarewellOS Package Manager
# Wrapper untuk Alpine apk CDN
# Binary ini wajib bernama 'party' sesuai spec soal

REPO="https://dl-cdn.alpinelinux.org/alpine/edge/main/x86_64"
CACHE_DIR="/var/party/cache"
INST_FILE="/var/party/installed/installed.list"

mkdir -p "$CACHE_DIR" "$(dirname "$INST_FILE")"
[ -f "$INST_FILE" ] || touch "$INST_FILE"

usage() {
cat << 'USAGE'
party - FarewellOS Package Manager

Usage:
  party add <package>    Install package
  party del <package>    Remove package dari list
  party update           Update package index
  party list             Tampilkan package terinstall
  party search <query>   Cari package

Contoh:
  party add curl
  party add wget
  party update
USAGE
}

do_add() {
    [ -z "$1" ] && { echo "party: error: nama package harus diisi"; exit 1; }
    PKG="$1"
    echo "party: installing ${PKG}..."

    TMPFILE="${CACHE_DIR}/${PKG}.apk"
    PKG_URL="${REPO}/${PKG}.apk"

    if ! wget -q --no-check-certificate "$PKG_URL" -O "$TMPFILE"; then
        # Coba cari versi dengan suffix
        echo "party: mencari versi terbaru ${PKG}..."
        # Fetch index dulu kalau ada
        if [ -f "${CACHE_DIR}/APKINDEX" ]; then
            VER=$(grep -A3 "^P:${PKG}$" "${CACHE_DIR}/APKINDEX" | grep "^V:" | head -1 | cut -d: -f2)
            ARCH=$(uname -m)
            [ -n "$VER" ] && wget -q --no-check-certificate \
                "${REPO}/${PKG}-${VER}.apk" -O "$TMPFILE" 2>/dev/null || true
        fi
    fi

    if [ ! -s "$TMPFILE" ]; then
        echo "party: error: tidak bisa download ${PKG}. Cek nama atau koneksi."
        rm -f "$TMPFILE"
        return 1
    fi

    # Extract .apk (format tar.gz)
    EXTRACT="/tmp/party_extract_$$"
    mkdir -p "$EXTRACT"
    cd "$EXTRACT"
    tar xzf "$TMPFILE" 2>/dev/null || {
        # Coba gunzip dulu
        cp "$TMPFILE" /tmp/pkg_raw_$$
        gunzip -c /tmp/pkg_raw_$$ | tar x 2>/dev/null || true
        rm -f /tmp/pkg_raw_$$
    }

    # Copy files ke root filesystem
    # Abaikan .PKGINFO dan metadata
    for d in bin sbin usr lib etc; do
        [ -d "$d" ] && cp -r "$d"/* "/$d/" 2>/dev/null || true
    done

    cd /
    rm -rf "$EXTRACT" "$TMPFILE"

    grep -qxF "$PKG" "$INST_FILE" || echo "$PKG" >> "$INST_FILE"
    echo "party: ${PKG} berhasil diinstall."
}

do_del() {
    [ -z "$1" ] && { echo "party: error: nama package harus diisi"; exit 1; }
    sed -i "/^${1}$/d" "$INST_FILE" 2>/dev/null || true
    echo "party: ${1} dihapus dari daftar installed."
}

do_update() {
    echo "party: update index dari ${REPO}..."
    if wget -q --no-check-certificate \
        "${REPO}/APKINDEX.tar.gz" -O "${CACHE_DIR}/APKINDEX.tar.gz"; then
        tar xzf "${CACHE_DIR}/APKINDEX.tar.gz" -O > "${CACHE_DIR}/APKINDEX" 2>/dev/null || true
        echo "party: index berhasil diupdate."
    else
        echo "party: gagal update index. Periksa koneksi internet."
        return 1
    fi
}

do_list() {
    echo "party: package terinstall:"
    if [ -s "$INST_FILE" ]; then
        cat "$INST_FILE"
    else
        echo "(belum ada package terinstall)"
    fi
}

do_search() {
    [ -z "$1" ] && { echo "party: error: query harus diisi"; exit 1; }
    if [ ! -f "${CACHE_DIR}/APKINDEX" ]; then
        echo "party: run 'party update' terlebih dahulu"
        return 1
    fi
    echo "party: hasil pencarian '${1}':"
    grep -i "^P:.*${1}" "${CACHE_DIR}/APKINDEX" | sed 's/^P:/  /' | head -20
}

case "$1" in
    add)    do_add    "$2" ;;
    del)    do_del    "$2" ;;
    update) do_update ;;
    list)   do_list ;;
    search) do_search "$2" ;;
    -h|--help|help|"") usage ;;
    *) echo "party: perintah tidak dikenal: $1"; usage; exit 1 ;;
esac
PARTY
chmod +x "$BUILD_DIR/bin/party"
echo "[✓] Package manager 'party' dibuat."

# ── Shared libraries (untuk binary dinamis) ───────────────────────────────────
echo "[*] Copy shared libraries..."
LIB64="/lib/x86_64-linux-gnu"
DEST64="$BUILD_DIR/lib/x86_64-linux-gnu"
mkdir -p "$DEST64" "$BUILD_DIR/lib64"

for lib in \
    "$LIB64/libc.so.6" \
    "$LIB64/libpthread.so.0" \
    "$LIB64/libdl.so.2" \
    "$LIB64/libresolv.so.2" \
    "$LIB64/libnss_dns.so.2" \
    "$LIB64/libnss_files.so.2" \
    "$LIB64/libm.so.6"; do
    [ -f "$lib" ] && cp "$lib" "$DEST64/" && echo "  copied: $(basename $lib)" || true
done

[ -f /lib64/ld-linux-x86-64.so.2 ] && \
    cp /lib64/ld-linux-x86-64.so.2 "$BUILD_DIR/lib64/" && \
    echo "  copied: ld-linux-x86-64.so.2"

# Copy fuse libs jika tersedia (untuk poin 10)
for fuselib in $(ldconfig -p 2>/dev/null | grep -E 'libfuse' | awk '{print $NF}' | head -4); do
    DESTDIR="$BUILD_DIR$(dirname "$fuselib")"
    mkdir -p "$DESTDIR"
    cp "$fuselib" "$DESTDIR/" 2>/dev/null && echo "  copied: $(basename $fuselib)" || true
done

# Copy fusermount
for fbin in fusermount3 fusermount; do
    FPATH=$(command -v "$fbin" 2>/dev/null) || true
    if [ -n "$FPATH" ]; then
        cp "$FPATH" "$BUILD_DIR/bin/$(basename "$FPATH")"
        chmod +x "$BUILD_DIR/bin/$(basename "$FPATH")"
        echo "  copied: $(basename "$FPATH")"
    fi
done

# ── Compile FUSE hello-world (poin 10 — dipersiapkan di multi) ───────────────
echo "[*] Compile FUSE hello-world program..."
FUSE_SRC="/tmp/fuse_hello_$$.c"
cat > "$FUSE_SRC" << 'FUSEC'
#define FUSE_USE_VERSION 31
#include <fuse3/fuse.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>

static const char *content = "Hello from FarewellOS FUSE!\n";
static const char *fname   = "/hello.txt";

static int fa_getattr(const char *path, struct stat *st,
                      struct fuse_file_info *fi)
{
    (void)fi;
    memset(st, 0, sizeof(*st));
    if (!strcmp(path, "/"))     { st->st_mode = S_IFDIR|0755; st->st_nlink = 2; return 0; }
    if (!strcmp(path, fname))   { st->st_mode = S_IFREG|0444; st->st_nlink = 1;
                                  st->st_size = strlen(content); return 0; }
    return -ENOENT;
}

static int fa_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                      off_t offset, struct fuse_file_info *fi,
                      enum fuse_readdir_flags flags)
{
    (void)offset; (void)fi; (void)flags;
    if (strcmp(path, "/")) return -ENOENT;
    filler(buf, ".",         NULL, 0, 0);
    filler(buf, "..",        NULL, 0, 0);
    filler(buf, "hello.txt", NULL, 0, 0);
    return 0;
}

static int fa_open(const char *path, struct fuse_file_info *fi)
{
    if (strcmp(path, fname)) return -ENOENT;
    if ((fi->flags & O_ACCMODE) != O_RDONLY) return -EACCES;
    return 0;
}

static int fa_read(const char *path, char *buf, size_t size, off_t offset,
                   struct fuse_file_info *fi)
{
    (void)fi;
    if (strcmp(path, fname)) return -ENOENT;
    size_t len = strlen(content);
    if (offset >= (off_t)len) return 0;
    if ((size_t)offset + size > len) size = len - (size_t)offset;
    memcpy(buf, content + offset, size);
    return (int)size;
}

static const struct fuse_operations fa_ops = {
    .getattr = fa_getattr,
    .readdir = fa_readdir,
    .open    = fa_open,
    .read    = fa_read,
};

int main(int argc, char *argv[])
{
    return fuse_main(argc, argv, &fa_ops, NULL);
}
FUSEC

# Simpan source ke /root di OS untuk referensi
cp "$FUSE_SRC" "$BUILD_DIR/root/fuse_hello.c"

# Compile
COMPILED=0
if pkg-config --exists fuse3 2>/dev/null; then
    CFLAGS_FUSE=$(pkg-config --cflags fuse3)
    LIBS_FUSE=$(pkg-config --libs fuse3)
    if gcc -Wall -D_FILE_OFFSET_BITS=64 $CFLAGS_FUSE "$FUSE_SRC" \
           -o "$BUILD_DIR/bin/fuse_hello" $LIBS_FUSE 2>/dev/null; then
        echo "[✓] fuse_hello berhasil dikompilasi."
        COMPILED=1
    fi
fi

if [ "$COMPILED" -eq 0 ] && pkg-config --exists fuse 2>/dev/null; then
    # Fallback ke FUSE 2 API
    sed 's|fuse3/fuse.h|fuse.h|; s|FUSE_USE_VERSION 31|FUSE_USE_VERSION 26|' \
        "$FUSE_SRC" > /tmp/fuse_hello2_$$.c
    CFLAGS_FUSE=$(pkg-config --cflags fuse)
    LIBS_FUSE=$(pkg-config --libs fuse)
    gcc -Wall -D_FILE_OFFSET_BITS=64 $CFLAGS_FUSE /tmp/fuse_hello2_$$.c \
        -o "$BUILD_DIR/bin/fuse_hello" $LIBS_FUSE 2>/dev/null && \
        echo "[✓] fuse_hello dikompilasi dengan FUSE2." && COMPILED=1
    rm -f /tmp/fuse_hello2_$$.c
fi

if [ "$COMPILED" -eq 0 ]; then
    echo "[!] Kompilasi FUSE gagal. Source tersedia di /root/fuse_hello.c"
    # Placeholder agar file ada
    cat > "$BUILD_DIR/bin/fuse_hello" << 'EOF'
#!/bin/sh
echo "fuse_hello: binary belum dikompilasi."
echo "Source ada di /root/fuse_hello.c"
echo "Jalankan: party add fuse-dev && gcc -D_FILE_OFFSET_BITS=64 /root/fuse_hello.c -o /bin/fuse_hello -lfuse3"
EOF
    chmod +x "$BUILD_DIR/bin/fuse_hello"
fi
rm -f "$FUSE_SRC"

# Script demo FUSE
cat > "$BUILD_DIR/bin/run_fuse_demo" << 'EOF'
#!/bin/sh
echo "=== FarewellOS FUSE Demo ==="
mkdir -p /mnt/fuse_hello
echo "[*] Mount fuse_hello di /mnt/fuse_hello..."
fuse_hello /mnt/fuse_hello &
sleep 1
echo "[*] Isi /mnt/fuse_hello:"
ls /mnt/fuse_hello
echo "[*] Baca hello.txt:"
cat /mnt/fuse_hello/hello.txt
echo "[*] Unmount..."
fusermount3 -u /mnt/fuse_hello 2>/dev/null || \
fusermount  -u /mnt/fuse_hello 2>/dev/null || true
echo "[✓] Done."
EOF
chmod +x "$BUILD_DIR/bin/run_fuse_demo"

# ── init script ───────────────────────────────────────────────────────────────
echo "[*] Buat init script..."
cat > "$BUILD_DIR/init" << 'EOF'
#!/bin/sh

# Mount filesystem essential
/bin/mount -t proc    none /proc
/bin/mount -t sysfs   none /sys
/bin/mount -t devtmpfs none /dev 2>/dev/null || /bin/mdev -s

# Perbaiki permission /dev/fuse
chmod 666 /dev/fuse 2>/dev/null || true

# Hostname
/bin/hostname farewell-multi

# /tmp world-writable
chmod 1777 /tmp

export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# Loopback interface
ifconfig lo up 2>/dev/null || ip link set lo up 2>/dev/null || true

# DHCP untuk eth0 (internet access - poin 8)
# udhcpc adalah DHCP client dari BusyBox
udhcpc -i eth0 -t 10 -n -q 2>/dev/null &

# Getty menampilkan login prompt di tty1
while true; do
    /bin/getty -L tty1 115200 vt100
    sleep 1
done
EOF
chmod +x "$BUILD_DIR/init"

# ── Pack initramfs ────────────────────────────────────────────────────────────
echo "[*] Packing initramfs..."
cd "$BUILD_DIR"
find . | cpio -oH newc 2>/dev/null | gzip -9 > "$OSBOOT_DIR/multi.gz"
cd "$SCRIPT_DIR"

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"

echo ""
echo "[✓] multi.sh selesai!"
echo "[✓] Output: $OSBOOT_DIR/multi.gz ($(du -h "$OSBOOT_DIR/multi.gz" | cut -f1))"
echo ""
echo "  Akun yang tersedia:"
echo "  root  / root123"
echo "  henn  / henn123"
echo "  hann  / hann123"
echo "  viii  / viii123"
echo "  kids  / kids123"
