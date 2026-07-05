#!/bin/bash
# SelfShield pour macOS — installation sans compte développeur, sans app.
#
# Trois couches, toutes appliquées par le SYSTÈME (aucun processus résident,
# 0 RAM/CPU/GPU dédiés, survit au redémarrage et à tout) :
#   1. Fichier /etc/hosts : ~45 000 domaines résolus vers 0.0.0.0
#      (le cache DNS système fait le travail, coût mémoire ~2 Mo de texte).
#   2. DNS filtrant Cloudflare for Families (bloque le reste au niveau
#      réseau, y compris les nouveaux domaines et sous-domaines).
#   3. Rappel des réglages Temps d'écran macOS à activer (filtre adulte
#      Safari + code détenu par une personne de confiance).
#
# Usage :
#   sudo ./install-macos.sh install     # installe hosts + DNS
#   sudo ./install-macos.sh update      # met à jour la liste hosts
#   sudo ./install-macos.sh uninstall   # retire tout
set -euo pipefail

HOSTS_URL="https://raw.githubusercontent.com/EDN2025-hub/edn-anki/main/selflock/data/hosts_blocklist.txt"
MARK_BEGIN="# >>> SelfShield begin >>>"
MARK_END="# <<< SelfShield end <<<"
LOCAL_LIST="$(dirname "$0")/../data/hosts_blocklist.txt"

require_root() { [ "$(id -u)" = 0 ] || { echo "Lancer avec sudo."; exit 1; }; }

fetch_list() {
    if curl -fsSL "$HOSTS_URL" -o /tmp/selfshield_hosts.txt 2>/dev/null; then
        echo "/tmp/selfshield_hosts.txt"
    elif [ -f "$LOCAL_LIST" ]; then
        echo "$LOCAL_LIST"
    else
        echo "Liste introuvable (réseau + copie locale)." >&2; exit 1
    fi
}

strip_block() {
    sed "/^${MARK_BEGIN}$/,/^${MARK_END}$/d" /etc/hosts > /tmp/hosts.clean
    cp /tmp/hosts.clean /etc/hosts
}

install_hosts() {
    LIST=$(fetch_list)
    cp /etc/hosts "/etc/hosts.selfshield.bak.$(date +%s)"
    strip_block
    { echo "$MARK_BEGIN"; cat "$LIST"; echo "$MARK_END"; } >> /etc/hosts
    dscacheutil -flushcache && killall -HUP mDNSResponder || true
    echo "hosts: $(grep -c '^0\.0\.0\.0' "$LIST") entrées installées."
}

install_dns() {
    # DNS filtrant sur toutes les interfaces réseau actives
    networksetup -listallnetworkservices | tail -n +2 | while read -r svc; do
        networksetup -setdnsservers "$svc" 1.1.1.3 1.0.0.3 || true
    done
    echo "DNS: Cloudflare for Families (1.1.1.3) appliqué à toutes les interfaces."
}

uninstall_all() {
    strip_block
    networksetup -listallnetworkservices | tail -n +2 | while read -r svc; do
        networksetup -setdnsservers "$svc" Empty || true
    done
    dscacheutil -flushcache && killall -HUP mDNSResponder || true
    echo "SelfShield retiré (hosts nettoyé, DNS remis en automatique)."
}

post_install_notes() {
    cat <<'EOF'

À FAIRE MANUELLEMENT (5 min, verrouillage fort) :
 1. Réglages Système > Temps d'écran > Contenu et confidentialité :
    - Contenu web : « Limiter les sites web pour adultes »
    - Ajouter twitter.com, x.com, reddit.com dans « Jamais autoriser »
      (liste complète : selflock/data/screentime_denylist.txt)
 2. Temps d'écran > Utiliser un code : faire SAISIR le code par une
    personne de confiance (sans le voir). Ce code verrouille aussi la
    modification des réglages DNS/hosts ci-dessus via les restrictions.
 3. Créer un compte macOS SÉPARÉ non-administrateur pour l'usage
    quotidien : sans droits admin, impossible de modifier /etc/hosts ou
    le DNS (le mot de passe admin peut aussi être détenu par le tiers).
EOF
}

require_root
case "${1:-install}" in
    install)   install_hosts; install_dns; post_install_notes ;;
    update)    install_hosts ;;
    uninstall) uninstall_all ;;
    *) echo "Usage: $0 {install|update|uninstall}"; exit 1 ;;
esac
