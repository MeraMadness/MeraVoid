#!/bin/bash

# Mount point
MOUNT_POINT=$1

# Check if mount point is provided
if [ -z "$MOUNT_POINT" ]; then
  echo "Usage: $0 <mount_point>"
  exit 1
fi

# Install KDE and necessary packages
chroot $MOUNT_POINT xbps-install -Sy kde5 kde5-baseapps kdegraphics-thumbnailers ffmpegthumbs dbus elogind pipewire linux-mainline linux-mainline-headers

# Install appropriate GPU driver
if [ "$GPU" == "AMD" ]; then
  chroot $MOUNT_POINT xbps-install -Sy void-repo-multilib-nonfree void-repo-nonfree void-repo-multilib
  chroot $MOUNT_POINT xbps-install -Sy amdgpu xf86-video-amdgpu mesa-dri mesa-dri-32bit vulkan-loader vulkan-loader-32bit mesa-vulkan-radeon mesa-vulkan-radeon-32bit xorg mesa-vaapi mesa-vdpau
elif [ "$GPU" == "NVIDIA" ]; then
  chroot $MOUNT_POINT xbps-install -Sy void-repo-nonfree void-repo-multilib-nonfree void-repo-multilib
  chroot $MOUNT_POINT xbps-install -Sy nvidia nvidia-dkms nvidia-libs nvidia-libs-32bit xorg
else
  echo "Unknown GPU type. No additional drivers installed."
fi

# Install Steam and Lutris for gaming
chroot $MOUNT_POINT xbps-install -Sy steam lutris

# Installing xbps-src
chroot $MOUNT_POINT xbps-install -Sy git
chroot $MOUNT_POINT git clone https://github.com/void-linux/void-packages.git
chroot $MOUNT_POINT cd void-packages
chroot $MOUNT_POINT ./xbps-src binary-bootstrap

# Enable SDDM
chroot $MOUNT_POINT ln -s /etc/sv/sddm /var/service/


