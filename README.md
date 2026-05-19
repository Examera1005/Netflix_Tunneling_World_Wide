# ResidentStream-Tunnel: Double-PC Tailscale Exit Node Setup

This repository provides architecture notes, documentation, and scripts to build a private residential hub-and-spoke gateway using **Tailscale (WireGuard)**.

The goal is to route traffic from a local media client (for example: smart projector or smart TV) through a local Wi-Fi relay, then encapsulate that traffic into an encrypted tunnel toward a remote residential exit node.

> French version: see [README.fr.md](./README.fr.md)

## 0. Install / Download Tailscale (Cross-platform)

Use one of the following installation paths depending on your OS.

### Ubuntu / Debian

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable --now tailscaled
```

### RedHat family (RHEL, Fedora, Rocky, AlmaLinux, CentOS Stream)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable --now tailscaled
```

### NixOS

Add Tailscale through NixOS configuration:

```nix
services.tailscale.enable = true;
```

Then rebuild:

```bash
sudo nixos-rebuild switch
```

### macOS

Option A (Homebrew):

```bash
brew install --cask tailscale
```

Option B: install from the Mac App Store (search for "Tailscale").

### Windows

Download from:
- https://tailscale.com/download

Then run PowerShell as Administrator for post-install MTU/ICS fix using [`windows-fix-mtu.ps1`](./windows-fix-mtu.ps1).

## 1. Network Architecture

The design uses a single physical radio interface on the local relay PC in concurrent mode (AP/STA), with on-path TCP segment tuning (MSS clamping / MTU reduction) to avoid network blackholes.
For low-level rationale (MTU model, control/data plane behavior, and `rp_filter`/`src_valid_mark`), see [ARCHITECTURE.md](./ARCHITECTURE.md).

```text
[ Projector / TV ]
│
▼ (5GHz Wi-Fi - same channel as uplink)
[ Local Relay PC (Kubuntu / Windows) ] ──► MTU reduction (1280) via ICS/iptables
│
▼ (Encrypted WireGuard Tunnel - UDP hole punching)
[ Remote Exit Node (CachyOS / Arch) ] ──► IP forwarding & kernel source validation fix
│
▼ (Residential WAN)
[ Internet ]
```

---

## 2. Exit Node Configuration (Remote Server - CachyOS / Arch Linux / Debian / Ubuntu)

The remote node acts as a transparent NAT router and should remain awake with the lid closed (for laptop-based hosts).

Preferred (automated) path:

- **CachyOS / Arch Linux**
  ```bash
  chmod +x ./cachyos-setup.sh
  sudo ./cachyos-setup.sh
  ```
- **Debian / Ubuntu**
  ```bash
  chmod +x ./debian-setup.sh
  sudo ./debian-setup.sh
  ```

Then continue directly to Step 4 (`tailscale up --advertise-exit-node`).

### Step 1: Install and persist daemon

```bash
sudo pacman -S tailscale
sudo systemctl enable --now tailscaled
```

### Step 2: Adjust Linux TCP/IP kernel behavior

Enable forwarding and account for source validation with marks:

```bash
sudo tee /etc/sysctl.d/99-tailscale.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.src_valid_mark = 1
EOF

sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
```

### Step 3: Prevent sleep on lid close

```bash
if grep -qE '^#?HandleLidSwitch=' /etc/systemd/logind.conf; then
  sudo sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
else
  echo 'HandleLidSwitch=ignore' | sudo tee -a /etc/systemd/logind.conf
fi
sudo systemctl restart systemd-logind
```

### Step 4: Bring Tailscale up as exit node

```bash
sudo tailscale up --advertise-exit-node
```

Then, in the Tailscale admin console, approve this machine as an exit node.

## 3. Local Relay Configuration (Client - Linux or Windows)

The local relay receives Internet from your home network and exposes a hotspot for the media device. All hotspot traffic should be steered into the `tailscale0` path.

### Option A: Linux implementation (Kubuntu / Debian)


Due to physical constraints on some Intel Wi-Fi chipsets (for example AX201), the hotspot should run on the same band/channel as uplink Wi-Fi.

1. **Identify active channel**
   ```bash
   nmcli -f IN-USE,CHAN,SSID device wifi list | grep '^\*'
   ```
2. **Create hotspot** (example: 5GHz, channel 44)
   ```bash
   nmcli device wifi hotspot ifname <YOUR_INTERFACE> ssid "Stream_Relais" password "<YOUR_STRONG_UNIQUE_PASSWORD>" band a channel 44
   ```
3. **Enable asymmetric routing through exit node**
   ```bash
   sudo tailscale up --exit-node=<TAILSCALE_SERVER_IP> --accept-dns=true --exit-node-allow-lan-access=true
   ```
4. **Add MSS clamping rule (iptables)**
   ```bash
   sudo iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
   sudo sh -c 'iptables-save > /etc/iptables/rules.v4'
   ```
   (Install `iptables-persistent` first if `/etc/iptables/rules.v4` is not present.)

### Option B: Windows 11/10 implementation

1. **Initialize Tailscale**: connect and select the remote node as Exit Node. Enable *Allow LAN access*.
2. **Hotspot**: enable Mobile Hotspot in Windows settings (prefer 5 GHz).
3. **ICS sharing**:
   - Run `ncpa.cpl`.
   - Right-click **Tailscale Tunnel** adapter > *Properties* > *Sharing* tab.
   - Enable *Allow other network users...* and select the Microsoft hotspot virtual adapter.
4. **Set MTU + restart ICS (PowerShell Admin)**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\windows-fix-mtu.ps1
   ```

### Option C: Raspberry Pi implementation (Raspberry Pi OS / Debian)

Preferred (automated) path:

```bash
chmod +x ./rpi-setup.sh
sudo ./rpi-setup.sh
```

This installs Tailscale, applies the required kernel sysctl settings, and persists the MSS clamping iptables rule across reboots via `iptables-persistent`.

Then configure the Pi as the Tailscale client relay:

```bash
sudo tailscale up --exit-node=<TAILSCALE_SERVER_IP> --accept-dns=true --exit-node-allow-lan-access=true
```

To expose a Wi-Fi hotspot from the Pi, install `hostapd` and `dnsmasq` and configure `wlan0` as an AP on the same band as your uplink.

## 4. Post-deployment Validation Protocol

From your target device browser (projector, Apple TV web view, etc.) connected to the relay hotspot:

1. Open `ifconfig.me`.
2. Returned IP must match the remote residential exit node public IP, not local ISP egress.
3. Check DNS leak behavior on `ipleak.net` to confirm DNS also exits through the tunnel.

## 5. Windows Reboot Maintenance Notes

After reboot, ICS can occasionally lose virtual routing alignment:

1. Disable then re-enable Mobile Hotspot.
2. In `ncpa.cpl`, open Tailscale adapter sharing properties, uncheck sharing, apply, then re-check to force NAT rule reinitialization.
