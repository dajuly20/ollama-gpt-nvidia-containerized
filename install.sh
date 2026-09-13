#!/bin/bash

# Ollama Docker Setup - Voraussetzungen & Installation Script
# Dieses Script prüft alle Voraussetzungen, installiert fehlende Komponenten
# und richtet das System für Ollama mit GPU-Unterstützung ein

set -e  # Bei Fehler abbrechen

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Farben, Konfiguration und alle Funktionen sind nach lib/setup-functions.sh ausgelagert
source "$SCRIPT_DIR/lib/setup-functions.sh"

# Script starten
main "$@"
