#!/usr/bin/env bash
# rpi-setup.sh — Local relay setup for Raspberry Pi (Debian/Raspberry Pi OS)
# Configures Tailscale client, kernel forwarding, and MSS clamping.
# Usage: sudo ./rpi-setup.sh
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "This script must be run as root (sudo)." >&2
  exit 1
fi

# Install Tailscale if not already present
# NOTE: piping curl to sh is the official Tailscale installation method.
# Review the script at https://tailscale.com/install.sh before running in
# security-sensitive environments.
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates debconf-utils

if ! command -v tailscaled >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

# Install iptables-persistent to survive reboots.
# Ensure debconf-set-selections exists, then pre-seed debconf to avoid
# interactive "save current rules?" prompts.
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent

# Kernel tuning: forwarding + source validation fix
install -d /etc/sysctl.d
cat >/etc/sysctl.d/99-tailscale.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.src_valid_mark = 1
SYSCTL

sysctl -p /etc/sysctl.d/99-tailscale.conf

# MSS clamping — prevents TCP blackhole through WireGuard encapsulation
iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
  iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

iptables-save >/etc/iptables/rules.v4

systemctl enable --now tailscaled

echo "Setup complete. Run next:"
echo "  sudo tailscale up --exit-node=<TAILSCALE_SERVER_IP> --accept-dns=true --exit-node-allow-lan-access=true"
