#!/bin/bash

# Green text
print_green() {
  echo -e "\033[1;32m$1\033[0m"
}

# Red text
print_red() {
  echo -e "\033[1;31m$1\033[0m"
}

# Function to detect GPU type
detect_gpu() {
  if lspci | grep -i amd &>/dev/null; then
    echo "AMD"
  elif lspci | grep -i nvidia &>/dev/null; then
    echo "NVIDIA"
  else
    echo "UNKNOWN"
  fi
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  print_red "Please run as root"
  exit
fi

# Introduction and Welcome
print_green "Welcome to the Void Linux for Gaming - Installer!"

# Display current partitions
print_green "Current partitions on all drives:"
fdisk -l
echo

# Prompt for necessary inputs
read -p "Enter the device to install Void Linux (e.g., /dev/sda): " DEVICE
read -p "Do you want to encrypt the drive? (yes/no): " ENCRYPT
read -p "Enter the hostname: " HOSTNAME
read -p "Enter the username: " USERNAME
read -sp "Enter the password for $USERNAME: " PASSWORD
echo 
read -p "Enter the locale (e.g., en_US.UTF-8): " LOCALE
read -p "Enter your timezone (e.g., Europe/Berlin): " TIMEZONE

# Select mirrors
print_green "Select the mirrors using xmirror"
xmirror -l /usr/share/xmirror/mirrors.lst

# Confirm the device to avoid data loss
print_red "WARNING: This will delete all data on $DEVICE."
read -p "Are you sure you want to continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  print_green "Installation aborted."
  exit
fi

# Set up partitions using sfdisk
print_green "Setting up partitions..."
sfdisk $DEVICE <<EOF
label: gpt
,512M,U
,,
EOF

# Format partitions
print_green "Formatting partitions..."
mkfs.fat -F32 ${DEVICE}1

if [ "$ENCRYPT" == "yes" ]; then
  print_green "Setting up LUKS encryption..."
  cryptsetup luksFormat ${DEVICE}2
  cryptsetup open ${DEVICE}2 cryptroot
  mkfs.btrfs /dev/mapper/cryptroot
  mount /dev/mapper/cryptroot /mnt
else
  mkfs.btrfs ${DEVICE}2
  mount ${DEVICE}2 /mnt
fi

# Create Btrfs subvolumes
print_green "Creating Btrfs subvolumes..."
mkdir -p /mnt/{home,.snapshots}
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var_log
umount /mnt

# Remount with subvolumes
print_green "Mounting subvolumes..."
mount -o noatime,compress=zstd,subvol=@ ${DEVICE}2 /mnt
mount -o noatime,compress=zstd,subvol=@home ${DEVICE}2 /mnt/home
mount -o noatime,compress=zstd,subvol=@snapshots ${DEVICE}2 /mnt/.snapshots
mkdir -p /mnt/var/log
mount -o noatime,compress=zstd,subvol=@var_log ${DEVICE}2 /mnt/var/log

# Verify Btrfs mounts
if ! mountpoint -q /mnt || ! mountpoint -q /mnt/home || ! mountpoint -q /mnt/.snapshots || ! mountpoint -q /mnt/var/log; then
  print_red "Error: One or more Btrfs subvolumes failed to mount."
  exit 1
fi

# Install base system
print_green "Installing base system..."
mkdir -p /mnt/boot/efi
mount ${DEVICE}1 /mnt/boot/efi
xbps-install -Sy -r /mnt base-system btrfs-progs sudo nano git base-devel efibootmgr mtools dosfstools grub-x86_64-efi grub-btrfs

# Configure fstab
print_green "Configuring fstab..."
UUID=$(blkid -s UUID -o value ${DEVICE}2)
BOOT_UUID=$(blkid -s UUID -o value ${DEVICE}1)
cat <<EOF > /mnt/etc/fstab
UUID=$UUID / btrfs rw,noatime,compress=zstd,subvol=@ 0 1
UUID=$UUID /home btrfs rw,noatime,compress=zstd,subvol=@home 0 2
UUID=$UUID /.snapshots btrfs rw,noatime,compress=zstd,subvol=@snapshots 0 2
UUID=$UUID /var/log btrfs rw,noatime,compress=zstd,subvol=@var_log 0 2
UUID=$BOOT_UUID /boot/efi vfat defaults,noatime 0 2
EOF

# Configure crypttab if encryption is enabled
if [ "$ENCRYPT" == "yes" ]; then
  print_green "Configuring crypttab..."
  echo "cryptroot UUID=$(blkid -s UUID -o value ${DEVICE}2) none luks" > /mnt/etc/crypttab
fi

# Set up system configurations
print_green "Setting up system configurations..."
echo $HOSTNAME > /mnt/etc/hostname
cat <<EOF > /mnt/etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# Set up locale
print_green "Setting up locale..."
echo "LANG=$LOCALE" > /mnt/etc/locale.conf
echo "$LOCALE UTF-8" > /mnt/etc/default/libc-locales

# Set up timezone
print_green "Setting up timezone..."
ln -sf /usr/share/zoneinfo/$TIMEZONE /mnt/etc/localtime
chroot /mnt hwclock --systohc --utc

# Install bootloader
print_green "Installing bootloader..."
for dir in dev proc sys run; do mount --rbind /$dir /mnt/$dir; mount --make-rslave /mnt/$dir; done

# Install GRUB
if [ "$ENCRYPT" == "yes" ]; then
  chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Void Linux"
  chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
  chroot /mnt xbps-reconfigure -fa
else
  chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Void Linux"
  chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
fi

# Add user and set password
print_green "Adding user and setting passwords..."
chroot /mnt useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chroot /mnt chpasswd
echo "root:$PASSWORD" | chroot /mnt chpasswd

# Detect GPU
GPU=$(detect_gpu)
print_green "Detected GPU: $GPU"

# Prompt for desktop environment selection
print_green "Select a desktop environment or Window Manager to install, also is going to install Steam, Lutris and Vesktop"
options=("KDE" "Gnome" "Hyprland" "Sway" "XFCE4")
select opt in "${options[@]}"
do
  case $opt in
    "KDE")
      /bin/bash kde.sh /mnt $GPU
      break
      ;;
    "Gnome")
      /bin/bash gnome.sh /mnt $GPU
      break
      ;;
    "Hyprland")
      /bin/bash hyprland.sh /mnt $GPU
      break
      ;;
    "Sway")
      /bin/bash sway.sh /mnt $GPU
      break
      ;;
    "XFCE4")
      /bin/bash xfce4.sh /mnt $GPU
      break
      ;;
    *) print_red "Invalid option $REPLY";;
  esac
done

# Finalize installation
print_green "Finalizing installation..."
umount -R /mnt

print_green "Installation complete. You can now reboot."


