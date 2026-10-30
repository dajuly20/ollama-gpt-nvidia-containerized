#!/bin/bash
# cleanup-580-drivers.sh
# Entfernt alle verwaisten NVIDIA-580-Pakete, damit nur der aktive 615-open-Treiber
# übrig bleibt. Hintergrund: Auf diesem Host (RTX A3000) war sowohl 580 als auch
# 615-open installiert; DKMS baut nur 615 für den laufenden Kernel. Die 580er sind
# teils nur noch Config-Reste (rc), teils verwaiste Firmware-Pakete (ii).
#
# Nutzt /usr/bin/apt-get direkt (apt ist auf diesem Host auf 'nala' gealiased).
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo -e "${BLUE}━━ NVIDIA 580-Treiber Aufräumen ━━${NC}"

# Alle noch bekannten 580-Pakete (egal ob ii oder rc) dynamisch sammeln
mapfile -t PKGS < <(dpkg-query -W -f='${Status}\t${Package}\n' 2>/dev/null \
    | grep -iE 'nvidia.*580' \
    | grep -vE 'not-installed' \
    | awk -F'\t' '{print $2}')

if [ "${#PKGS[@]}" -eq 0 ]; then
    echo -e "${GREEN}✓ Keine 580-Pakete mehr vorhanden – nichts zu tun.${NC}"
    exit 0
fi

echo -e "${YELLOW}Folgende 580-Pakete werden entfernt/gepurged:${NC}"
printf '  - %s\n' "${PKGS[@]}"
echo

# Sicherheits-Check: darf KEIN 615-Paket in der Liste sein
if printf '%s\n' "${PKGS[@]}" | grep -q '615'; then
    echo -e "${RED}✗ Abbruch: Liste enthält ein 615-Paket – das wäre falsch.${NC}"
    exit 1
fi

read -rp "Fortfahren? (j/n): " -n 1 REPLY; echo
[[ "$REPLY" =~ ^[JjYy]$ ]] || { echo "Abgebrochen."; exit 0; }

# purge entfernt sowohl ii- als auch rc-Pakete samt Config
sudo /usr/bin/apt-get purge -y "${PKGS[@]}"

echo
echo -e "${BLUE}━━ Verwaiste Abhängigkeiten aufräumen ━━${NC}"
sudo /usr/bin/apt-get autoremove -y

echo
echo -e "${GREEN}✓ Fertig.${NC} Verbleibende NVIDIA-Treiberpakete:"
dpkg -l | grep -iE 'nvidia-(driver|dkms)' | awk '{print "  " $1, $2, $3}'
echo
echo -e "${BLUE}DKMS-Status:${NC}"
dkms status | grep -i nvidia || echo "  (kein nvidia DKMS)"
