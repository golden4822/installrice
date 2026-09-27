#!/usr/bin/env bash
#
# install-summer-rice.sh
# Installs the "summer-day-and-night" Hyprland rice
# (https://github.com/MathisP75/summer-day-and-night)
# on Arch Linux with an NVIDIA GPU and a single monitor.
#
# Usage: chmod +x install-summer-rice.sh && ./install-summer-rice.sh
# Do NOT run as root. It will call sudo itself when needed.

set -e

if [ "$EUID" -eq 0 ]; then
  echo "Don't run this as root. Run it as your normal user; it will call sudo when needed."
  exit 1
fi

RICE_DIR="$HOME/summer-day-and-night"
CONFIG_BACKUP="$HOME/.config_backup_$(date +%s)"

echo "=== 1. Updating system ==="
sudo pacman -Syu --noconfirm

echo "=== 2. Installing NVIDIA driver stack ==="
# nvidia-dkms tracks whatever kernel you have installed (safer than plain `nvidia`
# if you're not on the stock `linux` package or you update kernels often)
sudo pacman -S --needed --noconfirm \
  nvidia-dkms nvidia-utils nvidia-settings linux-headers

echo "=== 3. Installing base rice dependencies ==="
sudo pacman -S --needed --noconfirm \
  hyprland waybar wofi kitty nemo firefox \
  ttf-jetbrains-mono-nerd \
  base-devel git \
  qt5-wayland qt6-wayland xdg-desktop-portal-hyprland polkit-kde-agent

echo "=== 4. Installing yay (AUR helper) ==="
if ! command -v yay >/dev/null 2>&1; then
  tmpdir=$(mktemp -d)
  git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
  (cd "$tmpdir/yay" && makepkg -si --noconfirm)
  rm -rf "$tmpdir"
else
  echo "yay already installed, skipping."
fi

echo "=== 5. Installing nitch (fetch tool) and nwg-look (GTK theme switcher) ==="
yay -S --needed --noconfirm nitch nwg-look

echo "=== 6. Cloning the rice repo ==="
if [ -d "$RICE_DIR" ]; then
  echo "  $RICE_DIR already exists, pulling latest instead of re-cloning."
  git -C "$RICE_DIR" pull
else
  git clone https://github.com/MathisP75/summer-day-and-night.git "$RICE_DIR"
fi

echo "=== 7. Backing up existing configs to $CONFIG_BACKUP ==="
mkdir -p "$CONFIG_BACKUP"
for d in hypr waybar wofi kitty; do
  if [ -d "$HOME/.config/$d" ]; then
    mv "$HOME/.config/$d" "$CONFIG_BACKUP/$d"
    echo "  backed up ~/.config/$d"
  fi
done

echo "=== 8. Copying rice configs into ~/.config ==="
for d in hypr waybar wofi kitty; do
  cp -r "$RICE_DIR/$d" "$HOME/.config/"
done

echo "=== 9. Copying wallpapers to ~/Pictures/wallpapers ==="
mkdir -p "$HOME/Pictures/wallpapers"
cp -r "$RICE_DIR/wallpapers/." "$HOME/Pictures/wallpapers/"

HYPR_CONF="$HOME/.config/hypr/hyprland.conf"

echo "=== 10. Patching hyprland.conf for NVIDIA ==="
if [ -f "$HYPR_CONF" ]; then
  cat >> "$HYPR_CONF" <<'EOF'

# --- Added by install-summer-rice.sh: NVIDIA compatibility ---
env = LIBVA_NVIDIA_DRIVER_NAME,nvidia
env = XDG_SESSION_TYPE,wayland
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = WLR_NO_HARDWARE_CURSORS,1
env = NVD_BACKEND,direct
EOF
  echo "  NVIDIA env vars appended to $HYPR_CONF"
else
  echo "  WARNING: $HYPR_CONF not found, skipping NVIDIA env var patch."
fi

echo "=== 11. Setting single-monitor auto config ==="
if [ -f "$HYPR_CONF" ]; then
  # Comment out any existing monitor= lines from the rice and force auto-detect
  sed -i 's/^monitor=.*/# &/' "$HYPR_CONF"
  echo "monitor=,preferred,auto,1" >> "$HYPR_CONF"
fi

echo "=== 12. Enabling NVIDIA DRM kernel mode setting ==="
# Required for Hyprland to work properly on NVIDIA
if ! grep -q "nvidia_drm.modeset=1" /etc/default/grub 2>/dev/null; then
  if [ -f /etc/default/grub ]; then
    sudo sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 nvidia_drm.modeset=1"/' /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    echo "  Added nvidia_drm.modeset=1 to GRUB and regenerated grub.cfg."
  else
    echo "  /etc/default/grub not found — if you use systemd-boot or another"
    echo "  bootloader, add nvidia_drm.modeset=1 to your kernel parameters manually."
  fi
fi

MKINITCPIO=/etc/mkinitcpio.conf
if ! grep -q "nvidia_drm" "$MKINITCPIO"; then
  sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uevent nvidia_drm)/' "$MKINITCPIO"
  sudo mkinitcpio -P
  echo "  Added nvidia modules to mkinitcpio.conf and regenerated initramfs."
fi

echo ""
echo "=========================================================="
echo " Install complete."
echo ""
echo " Manual steps still required:"
echo " 1. GTK theme + icons (Everforest) aren't on the AUR/repos —"
echo "    download them from gnome-look.org, then run 'nwg-look'"
echo "    to apply them:"
echo "      https://www.gnome-look.org/p/1695467 (GTK theme)"
echo "      https://www.gnome-look.org/p/1695476 (icons)"
echo " 2. Reboot now so the NVIDIA kernel changes take effect:"
echo "      sudo reboot"
echo " 3. At your login manager, select the Hyprland session."
echo " 4. Your old configs are backed up at: $CONFIG_BACKUP"
echo "=========================================================="
