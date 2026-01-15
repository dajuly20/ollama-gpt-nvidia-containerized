#!/bin/bash

# Ollama Docker Setup - Voraussetzungen & Installation Script
# Dieses Script prüft alle Voraussetzungen, installiert fehlende Komponenten
# und richtet das System für Ollama mit GPU-Unterstützung ein

set -e  # Bei Fehler abbrechen

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Standardwerte für Modellgrößen (in GB)
declare -A MODEL_SIZES=(
    ["llama3.2:1b"]=1.3
    ["llama3.2:3b"]=2.0
    ["mistral:7b"]=4.1
    ["llama3.1:8b"]=4.7
    ["dolphin-mistral:7b-v2.6"]=4.1
    ["nous-hermes2"]=6.1
    ["llama2:13b"]=7.4
    ["codellama:13b"]=7.4
    ["mixtral:8x7b"]=26.0
)

# Funktionen für formatierte Ausgabe
print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Funktion zum Prüfen, ob ein Befehl existiert
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Funktion zum Prüfen des verfügbaren Festplattenplatzes
check_disk_space() {
    local path="$1"
    local required_gb="$2"

    # Verfügbarer Platz in GB
    local available_gb=$(df -BG "$path" | awk 'NR==2 {print $4}' | sed 's/G//')

    if [ "$available_gb" -ge "$required_gb" ]; then
        return 0
    else
        return 1
    fi
}

# Funktion zum Abrufen des verfügbaren Festplattenplatzes
get_available_space() {
    local path="$1"
    df -h "$path" | awk 'NR==2 {print $4}'
}

# Funktion zum Prüfen der NVIDIA GPU
check_nvidia_gpu() {
    print_header "NVIDIA GPU Prüfung"

    if command_exists nvidia-smi; then
        print_success "nvidia-smi gefunden"

        # GPU-Informationen abrufen
        echo ""
        nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader | while IFS=',' read -r name memory driver; do
            print_info "GPU: $name"
            print_info "VRAM: $memory"
            print_info "Treiber: $driver"
        done
        echo ""

        return 0
    else
        print_error "nvidia-smi nicht gefunden"
        print_warning "NVIDIA-Treiber sind nicht installiert oder nicht korrekt konfiguriert"
        return 1
    fi
}

# Funktion zum Prüfen von Docker
check_docker() {
    print_header "Docker Prüfung"

    if command_exists docker; then
        local docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        print_success "Docker installiert: Version $docker_version"

        # Prüfen, ob Docker läuft
        if docker ps >/dev/null 2>&1; then
            print_success "Docker-Daemon läuft"
            return 0
        else
            print_error "Docker-Daemon läuft nicht"
            print_info "Starte Docker mit: sudo systemctl start docker"
            return 1
        fi
    else
        print_error "Docker ist nicht installiert"
        return 1
    fi
}

# Funktion zum Prüfen von Docker Compose
check_docker_compose() {
    print_header "Docker Compose Prüfung"

    # Prüfen auf docker compose (Plugin) oder docker-compose (Standalone)
    if docker compose version >/dev/null 2>&1; then
        local compose_version=$(docker compose version --short)
        print_success "Docker Compose (Plugin) installiert: Version $compose_version"
        return 0
    elif command_exists docker-compose; then
        local compose_version=$(docker-compose --version | awk '{print $3}' | sed 's/,//')
        print_success "Docker Compose (Standalone) installiert: Version $compose_version"
        return 0
    else
        print_error "Docker Compose ist nicht installiert"
        return 1
    fi
}

# Funktion zum Prüfen des NVIDIA Container Toolkit
check_nvidia_toolkit() {
    print_header "NVIDIA Container Toolkit Prüfung"

    if dpkg -l | grep -q nvidia-container-toolkit; then
        local toolkit_version=$(dpkg -l | grep nvidia-container-toolkit | awk '{print $3}')
        print_success "NVIDIA Container Toolkit installiert: Version $toolkit_version"
        return 0
    else
        print_error "NVIDIA Container Toolkit ist nicht installiert"
        return 1
    fi
}

# Funktion zum Prüfen der Docker NVIDIA Runtime
check_docker_nvidia_runtime() {
    print_header "Docker NVIDIA Runtime Prüfung"

    if [ -f /etc/docker/daemon.json ]; then
        if grep -q "nvidia" /etc/docker/daemon.json; then
            print_success "NVIDIA Runtime in Docker konfiguriert"
            return 0
        else
            print_warning "NVIDIA Runtime NICHT in /etc/docker/daemon.json konfiguriert"
            return 1
        fi
    else
        print_warning "/etc/docker/daemon.json existiert nicht"
        return 1
    fi
}

# Funktion zum Installieren von Docker
install_docker() {
    print_header "Docker Installation"

    print_info "Installiere Docker..."

    # Docker GPG Key hinzufügen
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Docker Repository hinzufügen
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Docker installieren
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Benutzer zur Docker-Gruppe hinzufügen
    sudo usermod -aG docker $USER

    print_success "Docker erfolgreich installiert"
    print_warning "WICHTIG: Bitte melde dich ab und wieder an, damit Gruppenmitgliedschaft wirksam wird"
}

# Funktion zum Installieren des NVIDIA Container Toolkit
install_nvidia_toolkit() {
    print_header "NVIDIA Container Toolkit Installation"

    print_info "Installiere NVIDIA Container Toolkit..."

    # GPG Key und Repository hinzufügen
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    # Installieren
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit

    print_success "NVIDIA Container Toolkit erfolgreich installiert"
}

# Funktion zum Konfigurieren der Docker NVIDIA Runtime
configure_docker_nvidia_runtime() {
    print_header "Docker NVIDIA Runtime Konfiguration"

    print_info "Konfiguriere Docker für NVIDIA Runtime..."

    # Backup der existierenden Konfiguration (falls vorhanden)
    if [ -f /etc/docker/daemon.json ]; then
        sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup
        print_info "Backup erstellt: /etc/docker/daemon.json.backup"
    fi

    # NVIDIA Runtime konfigurieren
    sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "default-runtime": "nvidia"
}
EOF

    print_success "Docker NVIDIA Runtime konfiguriert"

    # Docker neu starten
    print_info "Starte Docker-Daemon neu..."
    sudo systemctl restart docker

    print_success "Docker-Daemon neu gestartet"
}

# Funktion zum Prüfen des Festplattenplatzes
check_storage() {
    print_header "Festplatten-Platz Prüfung"

    local ollama_path="/home/julian/ollama"
    local webui_path="/home/julian/open-webui"

    # Verfügbarer Platz für Ollama-Pfad
    local available=$(get_available_space "$(dirname "$ollama_path")")
    print_info "Verfügbarer Platz für Ollama-Daten: $available"

    echo ""
    print_info "Geschätzter Platzbedarf für Modelle:"
    echo ""

    # Modellgrößen anzeigen
    printf "%-30s %10s\n" "Modell" "Größe"
    echo "────────────────────────────────────────────"
    for model in "${!MODEL_SIZES[@]}"; do
        printf "%-30s %10s GB\n" "$model" "${MODEL_SIZES[$model]}"
    done | sort -t: -k2 -n

    echo ""

    # Minimaler Platzbedarf berechnen (kleinste 3 Modelle + Overhead)
    local min_space=10  # 10 GB Minimum
    local available_gb=$(df -BG "$(dirname "$ollama_path")" | awk 'NR==2 {print $4}' | sed 's/G//')

    if [ "$available_gb" -ge "$min_space" ]; then
        print_success "Genügend Festplattenplatz verfügbar (${available})"
    else
        print_warning "Wenig Festplattenplatz verfügbar (${available})"
        print_warning "Empfohlen: Mindestens 10 GB für Modelle"
    fi
}

# Funktion zum Erstellen der notwendigen Verzeichnisse
create_directories() {
    print_header "Verzeichnisse erstellen"

    local ollama_path="/home/julian/ollama"
    local webui_path="/home/julian/open-webui"

    if [ ! -d "$ollama_path" ]; then
        mkdir -p "$ollama_path"
        print_success "Verzeichnis erstellt: $ollama_path"
    else
        print_info "Verzeichnis existiert bereits: $ollama_path"
    fi

    if [ ! -d "$webui_path" ]; then
        mkdir -p "$webui_path"
        print_success "Verzeichnis erstellt: $webui_path"
    else
        print_info "Verzeichnis existiert bereits: $webui_path"
    fi
}

# Funktion zum automatischen Installieren aller fehlenden Komponenten
auto_install() {
    local needs_docker=false
    local needs_toolkit=false
    local needs_runtime_config=false

    # Prüfungen durchführen
    if ! check_docker >/dev/null 2>&1; then
        needs_docker=true
    fi

    if ! check_nvidia_toolkit >/dev/null 2>&1; then
        needs_toolkit=true
    fi

    if ! check_docker_nvidia_runtime >/dev/null 2>&1; then
        needs_runtime_config=true
    fi

    # Installation durchführen
    if [ "$needs_docker" = true ]; then
        echo ""
        read -p "Docker installieren? (j/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[JjYy]$ ]]; then
            install_docker
        fi
    fi

    if [ "$needs_toolkit" = true ]; then
        echo ""
        read -p "NVIDIA Container Toolkit installieren? (j/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[JjYy]$ ]]; then
            install_nvidia_toolkit
        fi
    fi

    if [ "$needs_runtime_config" = true ]; then
        echo ""
        read -p "Docker NVIDIA Runtime konfigurieren? (j/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[JjYy]$ ]]; then
            configure_docker_nvidia_runtime
        fi
    fi
}

# Funktion zum Anzeigen der laufenden Container
show_running_containers() {
    print_header "Laufende Container"

    if docker compose ps 2>/dev/null | grep -q "Up"; then
        echo ""
        # Formatierte Ausgabe der Container mit Ports
        docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
        echo ""

        # Services und ihre Ports extrahieren
        local webui_port
        local ollama_port
        webui_port=$(docker compose port open-webui 8080 2>/dev/null | cut -d: -f2)
        ollama_port=$(docker compose port ollama 11434 2>/dev/null | cut -d: -f2)

        if [ -n "$webui_port" ]; then
            print_success "Open WebUI läuft auf: http://localhost:${webui_port}"
        fi

        if [ -n "$ollama_port" ]; then
            print_success "Ollama API läuft auf: http://localhost:${ollama_port}"
        fi
    else
        print_warning "Keine Container laufen"
    fi
}

# Funktion zum Öffnen des Browsers
open_browser() {
    local url="$1"

    print_info "Öffne Browser: $url"

    # Versuche verschiedene Browser
    if command_exists xdg-open; then
        xdg-open "$url" >/dev/null 2>&1 &
    elif command_exists gnome-open; then
        gnome-open "$url" >/dev/null 2>&1 &
    elif command_exists firefox; then
        firefox "$url" >/dev/null 2>&1 &
    elif command_exists google-chrome; then
        google-chrome "$url" >/dev/null 2>&1 &
    elif command_exists chromium-browser; then
        chromium-browser "$url" >/dev/null 2>&1 &
    else
        print_warning "Kein Browser gefunden"
        print_info "Bitte öffne manuell: $url"
        return 1
    fi

    print_success "Browser geöffnet"
}

# Funktion zum Starten der Container
start_containers() {
    print_header "Container starten"

    if [ -f "docker-compose.yml" ]; then
        print_info "Starte Container mit docker compose..."
        docker compose up -d

        print_success "Container gestartet"

        echo ""
        print_info "Warte 5 Sekunden, bis Container hochgefahren sind..."
        sleep 5

        # Container-Status anzeigen
        show_running_containers

        echo ""
        # Frage, ob Browser geöffnet werden soll
        read -p "Möchtest du Open WebUI im Browser öffnen? (j/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[JjYy]$ ]]; then
            open_browser "http://localhost:3000"
        fi
    else
        print_error "docker-compose.yml nicht gefunden"
        return 1
    fi
}

# Funktion zum Verifizieren der GPU-Nutzung
verify_gpu_access() {
    print_header "GPU-Zugriff im Container verifizieren"

    print_info "Prüfe GPU-Zugriff im Ollama-Container..."

    if docker exec ollama nvidia-smi >/dev/null 2>&1; then
        print_success "GPU ist im Container zugänglich"
        echo ""
        docker exec ollama nvidia-smi
    else
        print_error "GPU ist NICHT im Container zugänglich"
        print_warning "Überprüfe die Docker NVIDIA Runtime Konfiguration"
        return 1
    fi
}

# Funktion zum Abrufen installierter Modelle
check_installed_models() {
    print_header "Installierte Modelle"

    if ! docker ps | grep -q "ollama"; then
        print_warning "Ollama-Container läuft nicht"
        print_info "Starte erst die Container mit Option 4"
        return 1
    fi

    print_info "Prüfe installierte Modelle..."
    echo ""

    # Installierte Modelle abrufen
    local models_output
    models_output=$(docker exec ollama ollama list 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$models_output" ]; then
        # Modelle gefunden
        echo "$models_output"
        echo ""

        # Anzahl der Modelle zählen (Header ausschließen)
        local model_count
        model_count=$(echo "$models_output" | tail -n +2 | wc -l)

        if [ "$model_count" -gt 0 ]; then
            print_success "$model_count Modell(e) installiert"

            # Gesamtgröße berechnen
            local total_size
            total_size=$(docker exec ollama du -sh /root/.ollama/models 2>/dev/null | awk '{print $1}')
            if [ -n "$total_size" ]; then
                print_info "Gesamtgröße der Modelle: $total_size"
            fi
        else
            print_warning "Keine Modelle installiert"
        fi
    else
        print_warning "Keine Modelle installiert"
    fi
}

# Funktion zur System-Analyse
analyze_system() {
    print_header "System-Analyse & Hardware-Profil"

    echo ""

    # GPU Information
    if command_exists nvidia-smi; then
        local gpu_info
        local gpu_vram_mb
        local gpu_compute

        gpu_info=$(nvidia-smi --query-gpu=name,memory.total,compute_cap --format=csv,noheader)
        gpu_vram_mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
        local gpu_vram_gb=$((gpu_vram_mb / 1024))

        echo -e "${BLUE}━━━ GPU Hardware ━━━${NC}"
        echo "$gpu_info" | while IFS=',' read -r name vram compute; do
            print_info "GPU Modell: $name"
            print_info "VRAM: $vram"
            print_info "Compute Capability: $compute"
        done
        echo ""
    fi

    # CPU Information
    echo -e "${BLUE}━━━ CPU Hardware ━━━${NC}"
    local cpu_model
    local cpu_cores
    local cpu_threads

    cpu_model=$(lscpu | grep "Modellname:" | cut -d: -f2 | xargs)
    cpu_cores=$(lscpu | grep "^Kern(e) pro Socket:" | awk '{print $NF}')
    cpu_threads=$(lscpu | grep "^CPU(s):" | head -1 | awk '{print $NF}')

    if [ -z "$cpu_model" ]; then
        cpu_model=$(lscpu | grep "Model name:" | cut -d: -f2 | xargs)
    fi
    if [ -z "$cpu_cores" ]; then
        cpu_cores=$(lscpu | grep "Core(s) per socket:" | awk '{print $NF}')
    fi

    print_info "CPU: $cpu_model"
    print_info "Kerne: ${cpu_cores:-N/A} Cores / ${cpu_threads:-N/A} Threads"
    echo ""

    # RAM Information
    echo -e "${BLUE}━━━ RAM ━━━${NC}"
    local ram_total
    local ram_available

    # Support both English and German free output
    ram_total=$(free -h | grep -E "^Mem:|^Speicher:" | awk '{print $2}')
    ram_available=$(free -h | grep -E "^Mem:|^Speicher:" | awk '{print $7}')

    print_info "RAM Gesamt: $ram_total"
    print_info "RAM Verfügbar: $ram_available"
    echo ""

    # System-Bewertung
    echo -e "${BLUE}━━━ System-Bewertung ━━━${NC}"

    local performance_tier="Unknown"
    local recommendation=""

    # Bewertung basierend auf GPU VRAM
    if [ -n "$gpu_vram_gb" ]; then
        if [ "$gpu_vram_gb" -ge 24 ]; then
            performance_tier="🏆 Enthusiast (24+ GB VRAM)"
            recommendation="Du kannst ALLE Modelle nutzen, inklusive Mixtral 8x7B und größer!"
        elif [ "$gpu_vram_gb" -ge 12 ]; then
            performance_tier="🥇 High-End (12-24 GB VRAM)"
            recommendation="Perfekt für große 13B+ Modelle. Nutze llama2:13b, codellama:13b oder nous-hermes2:13b"
        elif [ "$gpu_vram_gb" -ge 8 ]; then
            performance_tier="🥈 Mid-High (8-12 GB VRAM)"
            recommendation="Ideal für 7-13B Modelle. Empfohlen: llama3.1:8b, mistral:7b, gemma2:9b"
        elif [ "$gpu_vram_gb" -ge 6 ]; then
            performance_tier="🥉 Mid-Range (6-8 GB VRAM)"
            recommendation="Sehr gut für 7B Modelle. Optimal: mistral:7b, dolphin-mistral:7b, llama3.1:8b"
        elif [ "$gpu_vram_gb" -ge 4 ]; then
            performance_tier="📱 Entry (4-6 GB VRAM)"
            recommendation="Gut für kleine Modelle. Nutze: llama3.2:3b, phi3:mini, qwen2.5:3b"
        else
            performance_tier="💻 Low-End (<4 GB VRAM)"
            recommendation="Nur sehr kleine Modelle möglich: llama3.2:1b"
        fi

        print_success "Leistungsklasse: $performance_tier"
        print_info "$recommendation"
    fi

    echo ""
    return 0
}

# Funktion zum Anzeigen personalisierter Modell-Empfehlungen
show_personalized_recommendations() {
    print_header "Personalisierte Modell-Empfehlungen"

    # System analysieren
    local gpu_vram_mb
    local gpu_vram_gb=0

    if command_exists nvidia-smi; then
        gpu_vram_mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
        gpu_vram_gb=$((gpu_vram_mb / 1024))
    fi

    echo ""
    print_info "Deine Hardware: ${gpu_vram_gb} GB VRAM"
    echo ""

    # Empfehlungen basierend auf VRAM
    if [ "$gpu_vram_gb" -ge 24 ]; then
        echo -e "${GREEN}🏆 Top-Empfehlungen für dein System (24+ GB):${NC}"
        echo "────────────────────────────────────────────────────────────"
        printf "%-30s %10s %20s\n" "Modell" "Größe" "Verwendung"
        printf "%-30s %10s %20s\n" "mixtral:8x7b" "26 GB" "Beste Qualität"
        printf "%-30s %10s %20s\n" "llama2:70b" "39 GB" "Research-Level"
        printf "%-30s %10s %20s\n" "codellama:34b" "19 GB" "Code-Experte"

    elif [ "$gpu_vram_gb" -ge 12 ]; then
        echo -e "${GREEN}🥇 Top-Empfehlungen für dein System (12-24 GB):${NC}"
        echo "────────────────────────────────────────────────────────────"
        printf "%-30s %10s %20s\n" "Modell" "Größe" "Verwendung"
        printf "%-30s %10s %20s\n" "llama2:13b" "7.4 GB" "Allround Experte"
        printf "%-30s %10s %20s\n" "codellama:13b" "7.4 GB" "Code-Spezialist"
        printf "%-30s %10s %20s\n" "mistral:7b" "4.1 GB" "Schnell & Gut"

    elif [ "$gpu_vram_gb" -ge 6 ]; then
        echo -e "${GREEN}🥉 Top-Empfehlungen für dein System (6-8 GB):${NC}"
        echo "────────────────────────────────────────────────────────────"
        printf "%-30s %10s %20s\n" "Modell" "Größe" "Verwendung"
        printf "%-30s %10s %20s\n" "mistral:7b" "4.1 GB" "Beste Balance ⭐"
        printf "%-30s %10s %20s\n" "llama3.1:8b" "4.7 GB" "Sehr intelligent"
        printf "%-30s %10s %20s\n" "dolphin-mistral:7b-v2.6" "4.1 GB" "Uncensored"
        printf "%-30s %10s %20s\n" "deepseek-coder:6.7b" "3.8 GB" "Code-Experte"
        printf "%-30s %10s %20s\n" "gemma2:9b" "5.5 GB" "Von Google"
        printf "%-30s %10s %20s\n" "llama3.2:3b" "2.0 GB" "Sehr schnell"

    elif [ "$gpu_vram_gb" -ge 4 ]; then
        echo -e "${YELLOW}📱 Top-Empfehlungen für dein System (4-6 GB):${NC}"
        echo "────────────────────────────────────────────────────────────"
        printf "%-30s %10s %20s\n" "Modell" "Größe" "Verwendung"
        printf "%-30s %10s %20s\n" "llama3.2:3b" "2.0 GB" "Beste Wahl ⭐"
        printf "%-30s %10s %20s\n" "phi3:mini" "2.3 GB" "Reasoning"
        printf "%-30s %10s %20s\n" "qwen2.5:3b" "2.0 GB" "Mehrsprachig"

    else
        echo -e "${RED}💻 Empfehlungen für dein System (<4 GB):${NC}"
        echo "────────────────────────────────────────────────────────────"
        printf "%-30s %10s %20s\n" "Modell" "Größe" "Verwendung"
        printf "%-30s %10s %20s\n" "llama3.2:1b" "1.3 GB" "Einzige Option"
    fi

    echo ""
}

# Funktion zum Anzeigen verfügbarer Modelle und Installation
show_available_models() {
    print_header "Verfügbare Modelle zum Download"

    echo ""

    # Zuerst personalisierte Empfehlungen anzeigen
    show_personalized_recommendations

    echo ""
    print_info "Vollständige Modellübersicht:"
    echo ""

    # GPU VRAM ermitteln
    local gpu_vram
    if command_exists nvidia-smi; then
        gpu_vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
        gpu_vram=$((gpu_vram / 1024))  # MB zu GB
    fi

    # Kategorisierte Modellempfehlungen
    echo -e "${GREEN}Kleine Modelle (1-3B Parameter) - Sehr schnell${NC}"
    echo "────────────────────────────────────────────────────────────"
    printf "%-30s %10s %15s\n" "Modell" "Größe" "VRAM"
    printf "%-30s %10s %15s\n" "llama3.2:1b" "1.3 GB" "~2 GB"
    printf "%-30s %10s %15s\n" "llama3.2:3b" "2.0 GB" "~3 GB"
    printf "%-30s %10s %15s\n" "phi3:mini" "2.3 GB" "~3 GB"
    printf "%-30s %10s %15s\n" "qwen2.5:3b" "2.0 GB" "~3 GB"
    echo ""

    echo -e "${YELLOW}Mittlere Modelle (7-9B Parameter) - Beste Balance${NC}"
    echo "────────────────────────────────────────────────────────────"
    printf "%-30s %10s %15s\n" "Modell" "Größe" "VRAM"
    printf "%-30s %10s %15s\n" "mistral:7b" "4.1 GB" "~5 GB"
    printf "%-30s %10s %15s\n" "llama3.1:8b" "4.7 GB" "~6 GB"
    printf "%-30s %10s %15s\n" "dolphin-mistral:7b-v2.6" "4.1 GB" "~5 GB (Uncensored)"
    printf "%-30s %10s %15s\n" "gemma2:9b" "5.5 GB" "~6 GB"
    echo ""

    echo -e "${BLUE}Code-Modelle - Spezialisiert für Programmierung${NC}"
    echo "────────────────────────────────────────────────────────────"
    printf "%-30s %10s %15s\n" "Modell" "Größe" "VRAM"
    printf "%-30s %10s %15s\n" "codellama:7b" "4.1 GB" "~5 GB"
    printf "%-30s %10s %15s\n" "deepseek-coder:6.7b" "3.8 GB" "~5 GB"
    printf "%-30s %10s %15s\n" "starcoder2:7b" "4.0 GB" "~5 GB"
    echo ""

    echo -e "${RED}Große Modelle (13B+) - Nur für 8+ GB VRAM${NC}"
    echo "────────────────────────────────────────────────────────────"
    printf "%-30s %10s %15s\n" "Modell" "Größe" "VRAM"
    printf "%-30s %10s %15s\n" "llama2:13b" "7.4 GB" "~8 GB"
    printf "%-30s %10s %15s\n" "nous-hermes2" "6.1 GB" "~6 GB (knapp!)"
    printf "%-30s %10s %15s\n" "mixtral:8x7b" "26 GB" "~28 GB (zu groß!)"
    echo ""
}

# Funktion zum Installieren von Modellen
install_models() {
    print_header "Modelle installieren"

    if ! docker ps | grep -q "ollama"; then
        print_warning "Ollama-Container läuft nicht"
        print_info "Starte erst die Container mit Option 4"
        return 1
    fi

    # Verfügbare Modelle anzeigen
    show_available_models

    echo ""
    print_info "Welche Modelle möchtest du installieren?"
    echo ""
    echo "Beliebte Optionen:"
    echo "  1) llama3.2:3b - Klein und schnell (2 GB)"
    echo "  2) mistral:7b - Beste Balance (4.1 GB)"
    echo "  3) dolphin-mistral:7b-v2.6 - Uncensored (4.1 GB)"
    echo "  4) deepseek-coder:6.7b - Code-Spezialist (3.8 GB)"
    echo "  5) Eigenes Modell eingeben"
    echo "  6) Überspringen"
    echo ""

    read -p "Wähle eine Option (1-6): " model_choice

    local model_name=""
    case $model_choice in
        1)
            model_name="llama3.2:3b"
            ;;
        2)
            model_name="mistral:7b"
            ;;
        3)
            model_name="dolphin-mistral:7b-v2.6"
            ;;
        4)
            model_name="deepseek-coder:6.7b"
            ;;
        5)
            read -p "Modellname eingeben (z.B. llama3.1:8b): " model_name
            ;;
        6)
            print_info "Überspringe Modell-Installation"
            return 0
            ;;
        *)
            print_error "Ungültige Auswahl"
            return 1
            ;;
    esac

    if [ -n "$model_name" ]; then
        echo ""
        print_info "Installiere Modell: $model_name"
        print_warning "Dies kann einige Minuten dauern..."
        echo ""

        if docker exec ollama ollama pull "$model_name"; then
            echo ""
            print_success "Modell '$model_name' erfolgreich installiert!"

            # Weitere Modelle installieren?
            echo ""
            read -p "Möchtest du ein weiteres Modell installieren? (j/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[JjYy]$ ]]; then
                install_models
            fi
        else
            echo ""
            print_error "Fehler beim Installieren von '$model_name'"
        fi
    fi
}

# Hauptmenü
show_menu() {
    echo ""
    print_header "Ollama Docker Setup - Hauptmenü"
    echo ""

    # Zeige bereits installierte Modelle (wenn Container läuft)
    if docker ps 2>/dev/null | grep -q "ollama"; then
        echo -e "${BLUE}━━━ Bereits installierte Modelle ━━━${NC}"
        local models_list
        models_list=$(docker exec ollama ollama list 2>/dev/null | tail -n +2)

        if [ -n "$models_list" ]; then
            echo "$models_list" | while IFS= read -r line; do
                local model_name
                local model_size
                model_name=$(echo "$line" | awk '{print $1}')
                model_size=$(echo "$line" | awk '{print $3 " " $4}')
                echo -e "  ${GREEN}✓${NC} $model_name ($model_size)"
            done
        else
            echo -e "  ${YELLOW}⚠${NC} Keine Modelle installiert"
        fi
        echo ""
    fi

    echo "1) System-Analyse & Modell-Empfehlungen"
    echo "2) Alle Voraussetzungen prüfen"
    echo "3) Fehlende Komponenten installieren (automatisch)"
    echo "4) Festplattenplatz prüfen"
    echo "5) Container starten"
    echo "6) GPU-Zugriff verifizieren"
    echo "7) Laufende Container anzeigen"
    echo "8) Open WebUI im Browser öffnen"
    echo "9) Installierte Modelle (Details)"
    echo "10) Verfügbare Modelle anzeigen & installieren"
    echo "11) Vollständiges Setup (Prüfen + Installieren + Starten)"
    echo "12) Beenden"
    echo ""
}

# Funktion zum Prüfen aller Voraussetzungen
check_all_prerequisites() {
    local all_ok=true

    if ! check_nvidia_gpu; then
        all_ok=false
    fi
    echo ""

    if ! check_docker; then
        all_ok=false
    fi
    echo ""

    if ! check_docker_compose; then
        all_ok=false
    fi
    echo ""

    if ! check_nvidia_toolkit; then
        all_ok=false
    fi
    echo ""

    if ! check_docker_nvidia_runtime; then
        all_ok=false
    fi
    echo ""

    check_storage

    echo ""
    if [ "$all_ok" = true ]; then
        print_success "Alle Voraussetzungen erfüllt!"
    else
        print_warning "Einige Voraussetzungen fehlen"
        print_info "Wähle Option 2 zum automatischen Installieren"
    fi
}

# Funktion für vollständiges Setup
full_setup() {
    print_header "Vollständiges Setup"

    # Prüfungen
    check_all_prerequisites

    echo ""
    echo ""

    # Installation
    auto_install

    echo ""
    echo ""

    # Verzeichnisse erstellen
    create_directories

    echo ""
    echo ""

    # Container starten
    read -p "Container jetzt starten? (j/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[JjYy]$ ]]; then
        start_containers

        echo ""
        echo ""

        verify_gpu_access

        echo ""
        echo ""

        # Modelle installieren?
        read -p "Möchtest du jetzt Modelle installieren? (j/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[JjYy]$ ]]; then
            echo ""
            install_models
        fi
    fi

    echo ""
    echo ""
    print_success "Setup abgeschlossen!"
}

# Funktion zum Prüfen, ob Container bereits laufen
check_containers_running() {
    if docker compose ps 2>/dev/null | grep -q "Up"; then
        return 0  # Container laufen
    else
        return 1  # Container laufen nicht
    fi
}

# Hauptprogramm
main() {
    clear

    # Banner
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║        Ollama Docker Setup - Installation Script         ║"
    echo "║                  mit NVIDIA GPU Support                   ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""

    # Prüfen, ob als root ausgeführt
    if [ "$EUID" -eq 0 ]; then
        print_error "Bitte führe dieses Script NICHT als root aus"
        print_info "Das Script wird sudo verwenden, wenn nötig"
        exit 1
    fi

    # Prüfen, ob Container bereits laufen
    if check_containers_running; then
        print_success "Container laufen bereits!"
        echo ""
        show_running_containers
        echo ""

        # Frage, ob neu installiert werden soll
        print_info "Möchtest du neu installieren oder einfach den Browser öffnen?"
        echo ""
        echo "1) Browser öffnen (Standard, automatisch in 5 Sekunden)"
        echo "2) Neu installieren (Container stoppen und neu aufsetzen)"
        echo ""

        # 5 Sekunden Countdown mit Abbruchmöglichkeit
        local user_choice="1"
        for i in 5 4 3 2 1; do
            echo -ne "${YELLOW}Öffne Browser automatisch in ${i} Sekunden... (Drücke 2 für Neuinstallation)${NC} \r"
            if read -t 1 -n 1 -r input; then
                if [ "$input" = "2" ]; then
                    user_choice="2"
                    break
                fi
            fi
        done
        echo -ne "\033[2K\r"  # Zeile löschen

        if [ "$user_choice" = "1" ]; then
            # Browser öffnen
            echo ""
            print_info "Öffne Browser..."
            open_browser "http://localhost:3000"
            echo ""
            print_success "Browser wurde geöffnet!"
            print_info "Falls nicht automatisch geöffnet: http://localhost:3000"
            echo ""
            print_info "Script beendet. Verwende das Menü für weitere Optionen."
            exit 0
        else
            # Neuinstallation
            echo ""
            print_warning "Stoppe laufende Container für Neuinstallation..."
            docker compose down
            print_success "Container gestoppt"
            echo ""
        fi
    fi

    # Interaktives Menü oder direkte Ausführung
    if [ $# -eq 0 ]; then
        # Timer für automatisches Setup
        print_info "Starte automatisch 'Vollständiges Setup' in 5 Sekunden..."
        print_info "Drücke eine beliebige Taste, um das Menü anzuzeigen"
        echo ""

        # 5 Sekunden Countdown mit Abbruchmöglichkeit
        local auto_start=true
        for i in 5 4 3 2 1; do
            echo -ne "${YELLOW}Auto-Start in ${i} Sekunden...${NC} \r"
            read -t 1 -n 1 && auto_start=false && break
        done
        echo -ne "\033[2K\r"  # Zeile löschen

        # Wenn nicht abgebrochen, starte vollständiges Setup
        if [ "$auto_start" = true ]; then
            clear
            full_setup
            echo ""
            print_info "Setup abgeschlossen. Drücke Enter, um zum Menü zurückzukehren..."
            read -r
            clear
        else
            clear
        fi

        # Interaktives Menü
        while true; do
            show_menu
            read -p "Wähle eine Option: " choice
            case $choice in
                1)
                    clear
                    analyze_system
                    echo ""
                    show_personalized_recommendations
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                2)
                    clear
                    check_all_prerequisites
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                3)
                    clear
                    auto_install
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                4)
                    clear
                    check_storage
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                5)
                    clear
                    create_directories
                    start_containers
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                6)
                    clear
                    verify_gpu_access
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                7)
                    clear
                    show_running_containers
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                8)
                    clear
                    open_browser "http://localhost:3000"
                    sleep 2
                    clear
                    ;;
                9)
                    clear
                    check_installed_models
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                10)
                    clear
                    install_models
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                11)
                    clear
                    full_setup
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                12)
                    print_info "Auf Wiedersehen!"
                    exit 0
                    ;;
                *)
                    print_error "Ungültige Auswahl"
                    sleep 2
                    clear
                    ;;
            esac
        done
    else
        # Direkte Ausführung mit Parameter
        case $1 in
            --check)
                check_all_prerequisites
                ;;
            --install)
                auto_install
                ;;
            --start)
                create_directories
                start_containers
                ;;
            --full)
                full_setup
                ;;
            --help)
                echo "Verwendung: $0 [OPTION]"
                echo ""
                echo "Optionen:"
                echo "  --check     Alle Voraussetzungen prüfen"
                echo "  --install   Fehlende Komponenten installieren"
                echo "  --start     Container starten"
                echo "  --full      Vollständiges Setup (Prüfen + Installieren + Starten)"
                echo "  --help      Diese Hilfe anzeigen"
                echo ""
                echo "Ohne Parameter: Interaktives Menü"
                ;;
            *)
                print_error "Unbekannte Option: $1"
                print_info "Verwende --help für Hilfe"
                exit 1
                ;;
        esac
    fi
}

# Script starten
main "$@"
