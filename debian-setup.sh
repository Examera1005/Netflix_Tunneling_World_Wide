#!/usr/bin/env bash
# debian-setup.sh — Exit node setup for Debian / Ubuntu
# Usage: sudo ./debian-setup.sh
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "This script must be run as root (sudo)." >&2
  exit 1
fi

# Install Tailscale if not already present
# NOTE: piping curl to sh is the official Tailscale installation method.
# Review the script at https://tailscale.com/install.sh before running in
# security-sensitive environments.
if ! command -v tailscaled >/dev/null 2>&1; then
  apt-get update -qq
  curl -fsSL https://tailscale.com/install.sh | sh
fi

# Kernel tuning: forwarding + source validation fix
install -d /etc/sysctl.d
cat >/etc/sysctl.d/99-tailscale.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.src_valid_mark = 1
SYSCTL

sysctl -p /etc/sysctl.d/99-tailscale.conf

# Prevent sleep on lid close (laptop exit nodes)
if grep -qE '^#?HandleLidSwitch=' /etc/systemd/logind.conf; then
  sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
else
  printf '\nHandleLidSwitch=ignore\n' >>/etc/systemd/logind.conf
fi

systemctl enable --now tailscaled
systemctl restart systemd-logind

echo "Setup complete. Run next:"
echo "  tailscale up --advertise-exit-node"
