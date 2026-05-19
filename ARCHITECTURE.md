# ARCHITECTURE

## Vue d'ensemble

Le design repose sur un relais local (AP/STA) qui encapsule les flux applicatifs dans un tunnel WireGuard (via Tailscale) vers un nœud de sortie résidentiel distant. Le nœud distant agit comme routeur/NAT, avec forwarding activé et comportement noyau ajusté pour accepter les paquets marqués.

## Modèle MTU et MSS

Le tunnel ajoute un overhead d'encapsulation. Pour éviter la fragmentation ou les pertes silencieuses :

`MTU_effective = MTU_physique - Overhead`

- `MTU_physique` : MTU de l'interface sous-jacente.
- `Overhead` : en-têtes additionnels (UDP + WireGuard + IP, etc.).
- `MTU_effective` : taille maximale utile à respecter dans le tunnel.

Conséquence pratique : une MTU trop élevée côté client peut créer des blackholes (SYN/SYN-ACK passent, puis TLS/data échouent). La réduction à 1280 et/ou le `TCPMSS --clamp-mss-to-pmtu` stabilisent les sessions.

## Tailscale et WireGuard

Tailscale fournit un plan de contrôle (identité, ACL, coordination, DERP si nécessaire), tandis que le plan de données utilise WireGuard :

- encapsulation chiffrée des paquets,
- transport majoritairement UDP,
- hole punching quand possible,
- relais fallback (DERP) si pair direct impossible.

L'option Exit Node force le routage sortant du client via le nœud distant approuvé.

## Pourquoi rp_filter peut casser le routage

En Linux, le Strict Reverse Path Forwarding (`rp_filter=1`) vérifie que le chemin retour d'un paquet entrant correspond à l'interface d'entrée attendue. En routage asymétrique/tunnelisé, cette hypothèse est souvent fausse :

- paquet entrant via interface tunnel,
- route de retour estimée via autre interface,
- paquet rejeté comme spoofing.

Pour les topologies Tailscale/WireGuard avec marquage (`fwmark`), `net.ipv4.conf.all.src_valid_mark=1` permet au noyau de tenir compte du marquage dans la validation de source. Couplé à l'activation du forwarding, cela évite les rejets intempestifs tout en conservant une politique de sécurité cohérente.
