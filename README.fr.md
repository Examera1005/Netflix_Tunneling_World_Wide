# ResidentStream-Tunnel : Double-PC Tailscale Exit Node Setup

Ce dépôt fournit l'architecture, la documentation et les scripts nécessaires pour configurer une passerelle résidentielle privée asymétrique (Hub-and-Spoke) en utilisant **Tailscale (WireGuard)**. L'objectif est de router le trafic d'un client multimédia (ex: projecteur intelligent, Smart TV) à travers un point d'accès Wi-Fi local, puis de l'encapsuler dans un tunnel chiffré vers un nœud de sortie résidentiel distant afin de contourner les restrictions géographiques ou de foyer (ex: politiques de partage de compte Netflix).

## 1. Architecture Réseau

L'infrastructure repose sur l'exploitation d'une seule interface radio physique sur le PC relais, configurée en mode concurrent (AP/STA), associée à un mécanisme de modification de la taille des segments TCP à la volée (MSS Clamping / MTU Reduction) pour éviter le phénomène de "Blackhole" réseau.
Pour les détails bas niveau (modèle MTU, plan de contrôle/données, et interaction `rp_filter`/`src_valid_mark`), voir [ARCHITECTURE.md](./ARCHITECTURE.md).

```text
[ Projecteur / TV ]
│
▼ (Wi-Fi 5GHz - Même Canal que l'Uplink)
[ PC Relais Local (Kubuntu / Windows) ] ──► Réduction MTU (1280) via ICS/iptables
│
▼ (Tunnel WireGuard Chiffré - UDP Hole Punching)
[ Nœud de Sortie Distant (CachyOS / Arch) ] ──► IP Forwarding & Kernel Spoofing Fix
│
▼ (Réseau WAN Résidentiel)
[ Internet ]
```

---

## 2. Configuration du Nœud de Sortie (Serveur Distant - CachyOS / Arch Linux / Debian / Ubuntu)

Le serveur doit agir comme un routeur NAT transparent et ne pas passer en veille lors de la fermeture du capot (ACPI).

Chemin recommandé (automatisé) :

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

Ensuite, passez directement à l'étape 4 (`tailscale up --advertise-exit-node`).
Les étapes manuelles ci-dessous sont pour CachyOS / Arch Linux.

### Étape 1 : Installation et persistence du démon

```bash
sudo pacman -Syu tailscale
sudo systemctl enable --now tailscaled
```

### Étape 2 : Altération de la pile TCP/IP du Noyau

Pour autoriser le transfert des paquets et contourner le *Strict Reverse Path Forwarding* du noyau :

```bash
sudo tee /etc/sysctl.d/99-tailscale.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.src_valid_mark = 1
EOF

sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
```

### Étape 3 : Inhibition des états de veille (Lid Switch)

Pour maintenir la carte réseau active écran fermé :

```bash
if grep -qE '^#?HandleLidSwitch=' /etc/systemd/logind.conf; then
  sudo sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
else
  echo 'HandleLidSwitch=ignore' | sudo tee -a /etc/systemd/logind.conf
fi
sudo systemctl restart systemd-logind
```

### Étape 4 : Initialisation Tailscale

```bash
sudo tailscale up --advertise-exit-node
```

*Note : Vous devez impérativement vous rendre sur votre console d'administration Tailscale, localiser la machine et activer l'option "Use as exit node" dans les route settings.*

## 3. Configuration du Relais Local (Client - Mode Linux ou Windows)

Le PC relais reçoit Internet depuis la box locale et diffuse un Hotspot pour le projecteur. Tout le trafic du Hotspot doit être injecté dans l'interface virtuelle tailscale0.

### Option A : Implémentation sous Linux (Kubuntu 26.04)

En raison des contraintes physiques des puces Wi-Fi Intel (ex: AX201), le hotspot **doit** opérer sur le même canal et la même bande de fréquences que votre connexion Wi-Fi montante.

1. **Identifier le canal actif :**
   ```bash
   nmcli -f IN-USE,CHAN,SSID device wifi list | grep '^\*'
   ```
2. **Instancier le Hotspot (Exemple pour la bande 5GHz, canal 44) :**
   ```bash
   nmcli device wifi hotspot ifname <VOTRE_INTERFACE> ssid "Stream_Relais" password "<MOT_DE_PASSE_FORT_UNIQUE>" band a channel 44
   ```
3. **Établir le routage asymétrique Tailscale :**
   ```bash
   sudo tailscale up --exit-node=<IP_TAILSCALE_SERVEUR> --accept-dns=true --exit-node-allow-lan-access=true
   ```
4. **Injection de la règle de MSS Clamping (Netfilter/Iptables) :**
   L'encapsulation WireGuard réduit la MTU effective. Pour éviter le drop des paquets TLS :
   ```bash
   sudo iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
   sudo sh -c 'iptables-save > /etc/iptables/rules.v4'
   ```
   (Installez `iptables-persistent` au préalable si `/etc/iptables/rules.v4` n'existe pas.)

### Option B : Implémentation sous Windows (11/10)

1. **Initialisation :** Connectez Tailscale et sélectionnez le nœud CachyOS comme Exit Node. Cochez *Allow LAN access*.
2. **Hotspot :** Activez le "Point d'accès sans fil mobile" dans les paramètres Windows (Privilégiez la bande 5 GHz).
3. **Pontage réseau (ICS) :**
   - Exécutez `ncpa.cpl`.
   - Clic droit sur l'adaptateur **Tailscale Tunnel** > *Propriétés* > Onglet *Partage*.
   - Cochez *"Autoriser d'autres utilisateurs..."* et sélectionnez l'interface virtuelle correspondant au Hotspot Microsoft.
4. **Correction MTU + redémarrage ICS (PowerShell Admin) :**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\windows-fix-mtu.ps1
   ```

### Option C : Implémentation sur Raspberry Pi (Raspberry Pi OS / Debian)

Chemin recommandé (automatisé) :

```bash
chmod +x ./rpi-setup.sh
sudo ./rpi-setup.sh
```

Ce script installe Tailscale, applique les paramètres sysctl nécessaires et rend la règle MSS clamping persistante au redémarrage via `iptables-persistent`.

Configurez ensuite le Pi comme relais Tailscale :

```bash
sudo tailscale up --exit-node=<IP_TAILSCALE_SERVEUR> --accept-dns=true --exit-node-allow-lan-access=true
```

Pour exposer un hotspot Wi-Fi depuis le Pi, installez `hostapd` et `dnsmasq` et configurez `wlan0` en mode AP sur la même bande que votre connexion montante.

## 4. Protocole de Validation (Post-Déploiement)

Depuis le navigateur intégré de votre diffuseur final (Projecteur XGIMI, AppleTV, etc.) connecté au Wi-Fi du relais, validez l'étanchéité du tunnel :

1. Accédez à ifconfig.me.
2. L'adresse IP retournée doit être **l'IP publique résidentielle du serveur distant (Foyer Principal)**, et non celle de votre connexion locale.
3. Vérifiez l'absence de fuites DNS (DNS Leak) sur ipleak.net pour s'assurer que les requêtes de résolutions de noms passent également par l'Exit Node.

## 5. Maintenance et comportement post-reboot (Windows)

Après un redémarrage du PC relais Windows, le service ICS (Internet Connection Sharing) perd parfois l'alignement des tables de routage virtuelles :

1. Désactivez puis réactivez le Hotspot dans les paramètres Windows.
2. Ouvrez `ncpa.cpl`, allez dans les propriétés de partage de l'adaptateur Tailscale, décochez la case de partage, validez, puis recochez-la pour forcer Windows à réinstancier ses règles NAT.
