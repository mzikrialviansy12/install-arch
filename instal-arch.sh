#!/bin/bash
# ============================================================
#  Arch Linux Auto-Installer Script
#  Hostname  : my-ArchX86_64
#  Timezone  : Asia/Jakarta
#  Locale    : en_US.UTF-8
#  Bootloader: GRUB (UEFI)
# ============================================================

set -e

# ─── Warna output ───────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
header()  { echo -e "\n${BOLD}${GREEN}===== $* =====${NC}\n"; }

# ─── Pastikan berjalan sebagai root ─────────────────────────
[[ $EUID -ne 0 ]] && error "Script harus dijalankan sebagai root!"

# ─── Cek mode UEFI ──────────────────────────────────────────
[[ -d /sys/firmware/efi/efivars ]] || error "Sistem tidak berjalan dalam mode UEFI!"

# ============================================================
#  LANGKAH 1 — Pilih disk target
# ============================================================
header "LANGKAH 1: Pilih Disk Target"

lsblk -dpno NAME,SIZE,MODEL | grep -v "loop\|rom\|airoot"
echo ""
read -rp "Masukkan disk target (contoh: /dev/sda atau /dev/nvme0n1): " DISK

[[ -b "$DISK" ]] || error "Disk '$DISK' tidak ditemukan!"
warn "SEMUA DATA DI $DISK AKAN DIHAPUS!"
read -rp "Ketik 'ya' untuk melanjutkan: " KONFIRMASI
[[ "$KONFIRMASI" == "ya" ]] || error "Instalasi dibatalkan."

# Tentukan prefix partisi (nvme pakai p, sata/scsi tidak)
if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    PART="${DISK}p"
else
    PART="${DISK}"
fi

EFI_PART="${PART}1"
SWAP_PART="${PART}2"
ROOT_PART="${PART}3"

# ============================================================
#  LANGKAH 2 — Ukuran partisi
# ============================================================
header "LANGKAH 2: Konfigurasi Ukuran Partisi"

read -rp "Ukuran partisi EFI  (default: 512MiB)  : " EFI_SIZE
read -rp "Ukuran partisi SWAP (default: 4GiB)    : " SWAP_SIZE
EFI_SIZE=${EFI_SIZE:-512MiB}
SWAP_SIZE=${SWAP_SIZE:-4GiB}

info "EFI  → $EFI_SIZE"
info "SWAP → $SWAP_SIZE"
info "ROOT → sisa disk"

# ============================================================
#  LANGKAH 3 — Partisi disk
# ============================================================
header "LANGKAH 3: Membuat Partisi"

info "Menghapus tabel partisi lama..."
sgdisk --zap-all "$DISK" &>/dev/null

info "Membuat partisi GPT baru..."
sgdisk \
    --new=1:0:+${EFI_SIZE}  --typecode=1:ef00 --change-name=1:"EFI"  \
    --new=2:0:+${SWAP_SIZE} --typecode=2:8200 --change-name=2:"SWAP" \
    --new=3:0:0             --typecode=3:8300 --change-name=3:"ROOT" \
    "$DISK" &>/dev/null

partprobe "$DISK"
sleep 2

success "Partisi berhasil dibuat:"
lsblk "$DISK" -o NAME,SIZE,TYPE,PARTLABEL

# ============================================================
#  LANGKAH 4 — Format partisi
# ============================================================
header "LANGKAH 4: Memformat Partisi"

info "Format EFI  → FAT32 ($EFI_PART)"
mkfs.fat -F32 -n "EFI" "$EFI_PART"

info "Format SWAP ($SWAP_PART)"
mkswap -L "SWAP" "$SWAP_PART"

info "Format ROOT → ext4 ($ROOT_PART)"
mkfs.ext4 -L "ROOT" "$ROOT_PART"

success "Format selesai."

# ============================================================
#  LANGKAH 5 — Mount partisi
# ============================================================
header "LANGKAH 5: Mounting Partisi"

info "Mount ROOT ke /mnt"
mount "$ROOT_PART" /mnt

info "Membuat direktori /mnt/boot/efi"
mkdir -p /mnt/boot/efi

info "Mount EFI ke /mnt/boot/efi"
mount "$EFI_PART" /mnt/boot/efi

info "Aktifkan SWAP"
swapon "$SWAP_PART"

success "Mount selesai:"
lsblk "$DISK" -o NAME,SIZE,TYPE,MOUNTPOINT

# ============================================================
#  LANGKAH 6 — Pacstrap (instalasi sistem dasar)
# ============================================================
header "LANGKAH 6: Instalasi Sistem Dasar (pacstrap)"

info "Memperbarui keyring pacman..."
pacman -Sy --noconfirm archlinux-keyring &>/dev/null || true

info "Menjalankan pacstrap..."
pacstrap -K /mnt \
    base \
    linux \
    linux-firmware \
    vim \
    htop \
    fastfetch

success "pacstrap selesai."

# ============================================================
#  LANGKAH 7 — Generate fstab
# ============================================================
header "LANGKAH 7: Generate fstab"

genfstab -U /mnt >> /mnt/etc/fstab
success "fstab berhasil dibuat:"
cat /mnt/etc/fstab

# ============================================================
#  LANGKAH 8 — Konfigurasi sistem (arch-chroot)
# ============================================================
header "LANGKAH 8: Konfigurasi di dalam chroot"

arch-chroot /mnt /bin/bash <<CHROOT_EOF

set -e

# ── Timezone ──────────────────────────────────────────
echo "[CHROOT] Set timezone Asia/Jakarta"
ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
hwclock --systohc

# ── Locale ────────────────────────────────────────────
echo "[CHROOT] Konfigurasi locale"
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# ── Hostname ──────────────────────────────────────────
echo "[CHROOT] Set hostname"
echo "my-ArchX86_64" > /etc/hostname

# ── /etc/hosts ────────────────────────────────────────
echo "[CHROOT] Konfigurasi /etc/hosts"
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   my-ArchX86_64.localdomain my-ArchX86_64
EOF

# ── Password root ─────────────────────────────────────
echo "[CHROOT] Set password root"
echo "root:qwe123" | chpasswd

# ── Install GRUB (UEFI) ───────────────────────────────
echo "[CHROOT] Install GRUB dan efibootmgr"
pacman -S --noconfirm grub efibootmgr

echo "[CHROOT] Install GRUB ke EFI"
grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=GRUB \
    --recheck

echo "[CHROOT] Generate grub.cfg"
grub-mkconfig -o /boot/grub/grub.cfg

# ── NetworkManager ────────────────────────────────────
echo "[CHROOT] Install NetworkManager"
pacman -S --noconfirm networkmanager

echo "[CHROOT] Aktifkan NetworkManager service"
systemctl enable NetworkManager

echo "[CHROOT] Konfigurasi selesai!"
CHROOT_EOF

success "Konfigurasi chroot selesai."

# ============================================================
#  LANGKAH 9 — Unmount & Selesai
# ============================================================
header "LANGKAH 9: Unmount & Finalisasi"

info "Unmount semua partisi..."
umount -R /mnt
swapoff "$SWAP_PART"

success "Instalasi Arch Linux selesai!"
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       INSTALASI BERHASIL! 🎉              ║${NC}"
echo -e "${BOLD}║  Hostname : my-ArchX86_64                 ║${NC}"
echo -e "${BOLD}║  Timezone : Asia/Jakarta                  ║${NC}"
echo -e "${BOLD}║  Locale   : en_US.UTF-8                   ║${NC}"
echo -e "${BOLD}║  Bootloader: GRUB (UEFI)                  ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Pilihan reboot ────────────────────────────────────
read -rp "Reboot sekarang? (y/n): " REBOOT_NOW
if [[ "$REBOOT_NOW" =~ ^[Yy]$ ]]; then
    info "Sistem akan reboot dalam 3 detik..."
    sleep 3
    reboot
else
    warn "Reboot ditunda. Jalankan 'reboot' secara manual jika sudah siap."
fi
