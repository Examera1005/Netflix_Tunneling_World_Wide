#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ce script doit être exécuté en root (sudo)." >&2
  exit 1
fi

if ! command -v tailscaled >/dev/null 2>&1; then
  pacman -Syu --noconfirm tailscale
fi

install -d /etc/sysctl.d
cat >/etc/sysctl.d/99-tailscale.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.src_valid_mark = 1
SYSCTL

sysctl -p /etc/sysctl.d/99-tailscale.conf

if grep -qE '^#?HandleLidSwitch=' /etc/systemd/logind.conf; then
  sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
else
  printf '\nHandleLidSwitch=ignore\n' >>/etc/systemd/logind.conf
fi

systemctl enable --now tailscaled
systemctl restart systemd-logind

echo "Configuration terminée. Exécutez ensuite :"
echo "  tailscale up --advertise-exit-node"
