# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ncurses-Menü (dialog) - wird von ensure_dialog() gesetzt
DIALOG_BIN=""

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

# Funktion zum Prüfen, ob das NVIDIA-Kernelmodul geladen ist
check_nvidia_kernel_module() {
    print_header "NVIDIA Kernel-Modul Prüfung"

    if lsmod | grep -q "^nvidia "; then
        print_success "NVIDIA-Kernelmodul ist geladen"
        return 0
    else
        print_error "NVIDIA-Kernelmodul ist NICHT geladen"

        if dkms status 2>/dev/null | grep -q "^nvidia/.*$(uname -r).*: installed"; then
            print_info "DKMS-Modul ist für den laufenden Kernel ($(uname -r)) gebaut, aber nicht geladen"
            print_info "Meist hilft: sudo modprobe nvidia (oder ein Neustart nach einem Treiber-Update)"
        else
            print_warning "Kein DKMS-Build für den laufenden Kernel ($(uname -r)) gefunden"
            print_info "Der Treiber muss ggf. für diesen Kernel neu gebaut werden"
        fi
        return 1
    fi
}

# Funktion zum Prüfen auf mehrere gleichzeitig installierte NVIDIA-Treiberpakete
check_nvidia_driver_conflicts() {
    print_header "NVIDIA Treiberpaket-Konflikte Prüfung"

    local drivers
    drivers=$(dpkg -l | awk '/^ii/ && $2 ~ /^nvidia-driver-[0-9]+$/ {print $2}')
    local count=0
    [ -n "$drivers" ] && count=$(echo "$drivers" | wc -l)

    if [ "$count" -gt 1 ]; then
        print_warning "Mehrere NVIDIA-Treiberpakete gleichzeitig installiert:"
        echo "$drivers" | while read -r d; do print_info "  - $d"; done
        print_warning "Das kann dazu führen, dass das falsche Kernelmodul (oder gar keins) geladen wird"
        return 1
    elif [ "$count" -eq 1 ]; then
        print_success "Genau ein NVIDIA-Treiberpaket installiert: $drivers"
        return 0
    else
        print_error "Kein NVIDIA-Treiberpaket installiert"
        return 1
    fi
}

# Funktion zum Laden des NVIDIA-Kernelmoduls / Anstoßen eines Neustarts
load_nvidia_kernel_module() {
    print_header "NVIDIA Kernel-Modul laden"

    print_info "Versuche, das Kernelmodul zu laden (sudo modprobe nvidia)..."
    local err_file
    err_file=$(mktemp)
    if sudo modprobe nvidia 2>"$err_file" && sleep 1 && nvidia-smi >/dev/null 2>&1; then
        print_success "NVIDIA-Kernelmodul erfolgreich geladen"
        rm -f "$err_file"
        return 0
    fi

    print_error "Kernelmodul konnte nicht geladen werden"
    if [ -s "$err_file" ]; then
        print_info "Fehlermeldung: $(cat "$err_file")"
    fi
    rm -f "$err_file"
    print_warning "Ein Neustart ist meistens die zuverlässigste Lösung (z.B. nach einem Treiber-Update)"

    read -p "Jetzt neu starten? (j/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[JjYy]$ ]]; then
        print_info "System startet neu..."
        sudo reboot
    else
        print_info "Neustart übersprungen. Bitte manuell nachholen, sobald möglich."
    fi
    return 1
}

# Funktion: Gesamte GPU-Treiber Diagnose & Reparatur
fix_nvidia_gpu() {
    print_header "GPU-Treiber Diagnose & Reparatur"

    local module_ok=true

    if ! check_nvidia_driver_conflicts; then
        echo ""
        read -p "Ältere/doppelte Treiberpakete jetzt entfernen (nur das neueste behalten)? (j/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[JjYy]$ ]]; then
            local newest
            newest=$(dpkg -l | awk '/^ii/ && $2 ~ /^nvidia-driver-[0-9]+$/ {print $2}' | sort -t- -k3 -n | tail -1)
            echo ""
            print_info "Behalte: $newest"
            dpkg -l | awk '/^ii/ && $2 ~ /^nvidia-driver-[0-9]+$/ {print $2}' | grep -v "^${newest}$" | while read -r old; do
                print_info "Entferne: $old"
                sudo apt-get remove --purge -y "$old"
            done
            sudo apt-get autoremove -y
            print_success "Bereinigung abgeschlossen"
        fi
    fi

    echo ""
    check_nvidia_kernel_module || module_ok=false
    echo ""

    if [ "$module_ok" = false ]; then
        load_nvidia_kernel_module
        echo ""
    fi

    if ! check_nvidia_toolkit >/dev/null 2>&1; then
        read -p "NVIDIA Container Toolkit installieren? (j/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[JjYy]$ ]]; then
            install_nvidia_toolkit
        fi
    else
        print_success "NVIDIA Container Toolkit bereits installiert"
    fi

    echo ""
    if ! check_docker_nvidia_runtime >/dev/null 2>&1; then
        read -p "Docker NVIDIA Runtime konfigurieren? (j/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[JjYy]$ ]]; then
            configure_docker_nvidia_runtime
        fi
    else
        print_success "Docker NVIDIA Runtime bereits konfiguriert"
    fi

    echo ""
    print_header "Zusammenfassung"
    if command_exists nvidia-smi && nvidia-smi >/dev/null 2>&1; then
        print_success "nvidia-smi funktioniert - GPU ist auf dem Host verfügbar"
        print_info "Starte den ollama-Container neu, um GPU-Zugriff zu erhalten (Menüpunkt 'Container starten')"
    else
        print_error "nvidia-smi funktioniert weiterhin nicht"
        print_warning "Ein Neustart des Systems ist in den meisten Fällen die Lösung"
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

    if command_exists nvidia-ctk; then
        print_info "Konfiguriere Docker für NVIDIA Runtime via nvidia-ctk..."
        sudo nvidia-ctk runtime configure --runtime=docker
    else
        print_info "nvidia-ctk nicht gefunden, konfiguriere Docker manuell..."

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
    fi

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

# Funktion zum Auswählen eines Modellnamens per ncurses-Menü (dialog)
select_model_dialog() {
    local choice
    choice=$(dialog --stdout --clear --backtitle "Ollama Docker Setup" \
        --title "Modelle installieren" \
        --menu "Wähle ein Modell zum Herunterladen (Pfeiltasten + Enter):" 21 74 12 \
        "llama3.2:1b"             "Sehr klein, sehr schnell (1.3 GB)" \
        "llama3.2:3b"             "Klein und schnell (2.0 GB)" \
        "mistral:7b"              "Beste Balance (4.1 GB)" \
        "llama3.1:8b"             "Sehr intelligent (4.7 GB)" \
        "dolphin-mistral:7b-v2.6" "Uncensored (4.1 GB)" \
        "deepseek-coder:6.7b"     "Code-Spezialist (3.8 GB)" \
        "gemma2:9b"               "Von Google (5.5 GB)" \
        "codellama:13b"           "Code-Experte, 13B (7.4 GB)" \
        "eigenes"                 "Eigenen Modellnamen eingeben" \
        "fertig"                  "Fertig / Zurück zum Hauptmenü")
    local status=$?
    clear

    if [ $status -ne 0 ] || [ "$choice" = "fertig" ]; then
        return 1
    fi

    if [ "$choice" = "eigenes" ]; then
        choice=$(dialog --stdout --clear --title "Eigenes Modell" \
            --inputbox "Modellname (z.B. llama3.1:8b):" 8 60)
        clear
        [ -z "$choice" ] && return 1
    fi

    echo "$choice"
    return 0
}

# Funktion zum Auswählen eines Modellnamens per Text-Menü (Fallback ohne dialog)
select_model_plain() {
    echo ""
    echo "Beliebte Optionen:"
    echo "  1) llama3.2:3b - Klein und schnell (2 GB)"
    echo "  2) mistral:7b - Beste Balance (4.1 GB)"
    echo "  3) dolphin-mistral:7b-v2.6 - Uncensored (4.1 GB)"
    echo "  4) deepseek-coder:6.7b - Code-Spezialist (3.8 GB)"
    echo "  5) Eigenes Modell eingeben"
    echo "  6) Fertig"
    echo ""

    read -p "Wähle eine Option (1-6): " model_choice

    case $model_choice in
        1) echo "llama3.2:3b" ;;
        2) echo "mistral:7b" ;;
        3) echo "dolphin-mistral:7b-v2.6" ;;
        4) echo "deepseek-coder:6.7b" ;;
        5) read -p "Modellname eingeben (z.B. llama3.1:8b): " model_choice; echo "$model_choice" ;;
        6) return 1 ;;
        *) print_error "Ungültige Auswahl"; return 1 ;;
    esac
    return 0
}

# Funktion zum Prüfen, ob ein Modell bereits installiert ist
model_is_installed() {
    local model="$1"
    local installed
    installed=$(docker exec ollama ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')

    if echo "$installed" | grep -qx "$model"; then
        return 0
    fi

    # Wurde kein Tag angegeben, hängt Ollama automatisch ":latest" an
    if [[ "$model" != *:* ]] && echo "$installed" | grep -qx "${model}:latest"; then
        return 0
    fi

    return 1
}

# Funktion zum Nachfragen, ob ein bereits installiertes Modell neu installiert werden soll.
# Im Zweifelsfall (Enter/Standardauswahl) wird neu installiert (entfernt + neu heruntergeladen).
confirm_reinstall() {
    local model="$1"

    if [ "$DIALOG_BIN" = "dialog" ]; then
        dialog --clear --title "Modell bereits installiert" \
            --yes-label "Neu installieren" --no-label "Überspringen" \
            --yesno "Modell '$model' ist bereits installiert.\n\nNeu installieren (entfernen + neu herunterladen)?" 9 64
        local result=$?
        clear
        [ "$result" -eq 0 ] && return 0
        return 1
    else
        read -p "Modell '$model' ist bereits installiert. Neu installieren (entfernen + neu herunterladen)? Im Zweifel: Ja (J/n): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Nn]$ ]] && return 1
        return 0
    fi
}

# Funktion zum Installieren von Modellen
install_models() {
    print_header "Modelle installieren"

    if ! docker ps | grep -q "ollama"; then
        print_warning "Ollama-Container läuft nicht"
        print_info "Starte erst die Container (Menüpunkt 'Container starten')"
        return 1
    fi

    # Verfügbare Modelle einmalig anzeigen
    show_available_models
    read -p "Drücke Enter, um die Modell-Auswahl zu öffnen..."

    while true; do
        local model_name=""
        if [ "$DIALOG_BIN" = "dialog" ]; then
            model_name=$(select_model_dialog) || break
        else
            model_name=$(select_model_plain) || break
        fi

        [ -z "$model_name" ] && continue

        if model_is_installed "$model_name"; then
            print_warning "Modell '$model_name' ist bereits installiert"
            if confirm_reinstall "$model_name"; then
                echo ""
                print_info "Entferne bestehendes Modell '$model_name'..."
                docker exec ollama ollama rm "$model_name" >/dev/null 2>&1
                print_success "Altes Modell entfernt"
            else
                print_info "Überspringe '$model_name' (bereits installiert)"
                echo ""
                read -p "Drücke Enter, um fortzufahren..."
                continue
            fi
        fi

        echo ""
        print_info "Installiere Modell: $model_name"
        print_warning "Dies kann einige Minuten dauern..."
        echo ""

        if docker exec ollama ollama pull "$model_name"; then
            echo ""
            print_success "Modell '$model_name' erfolgreich installiert!"
        else
            echo ""
            print_error "Fehler beim Installieren von '$model_name'"
        fi
        echo ""
        read -p "Drücke Enter, um fortzufahren..."
    done
}

# Funktion zum Ermitteln der empfohlenen Modelle für eine bestimmte VRAM-Größe
# Füllt die globalen Arrays RECOMMENDED_MODELS und RECOMMENDED_DESCS
get_recommended_models() {
    local vram_gb="$1"
    RECOMMENDED_MODELS=()
    RECOMMENDED_DESCS=()

    if [ "$vram_gb" -ge 24 ]; then
        RECOMMENDED_MODELS=("mixtral:8x7b" "llama2:70b" "codellama:34b")
        RECOMMENDED_DESCS=("Beste Qualität (26 GB)" "Research-Level (39 GB)" "Code-Experte (19 GB)")
    elif [ "$vram_gb" -ge 12 ]; then
        RECOMMENDED_MODELS=("llama2:13b" "codellama:13b" "mistral:7b")
        RECOMMENDED_DESCS=("Allround Experte (7.4 GB)" "Code-Spezialist (7.4 GB)" "Schnell & Gut (4.1 GB)")
    elif [ "$vram_gb" -ge 6 ]; then
        RECOMMENDED_MODELS=("mistral:7b" "llama3.1:8b" "dolphin-mistral:7b-v2.6" "deepseek-coder:6.7b" "gemma2:9b" "llama3.2:3b")
        RECOMMENDED_DESCS=("Beste Balance (4.1 GB)" "Sehr intelligent (4.7 GB)" "Uncensored (4.1 GB)" "Code-Experte (3.8 GB)" "Von Google (5.5 GB)" "Sehr schnell (2.0 GB)")
    elif [ "$vram_gb" -ge 4 ]; then
        RECOMMENDED_MODELS=("llama3.2:3b" "phi3:mini" "qwen2.5:3b")
        RECOMMENDED_DESCS=("Beste Wahl (2.0 GB)" "Reasoning (2.3 GB)" "Mehrsprachig (2.0 GB)")
    else
        RECOMMENDED_MODELS=("llama3.2:1b")
        RECOMMENDED_DESCS=("Einzige Option (1.3 GB)")
    fi
}

# Funktion zum Auswählen mehrerer Modelle per ncurses-Checkbox (dialog)
# Erwartet, dass RECOMMENDED_MODELS/RECOMMENDED_DESCS bereits befüllt sind
# Gibt die ausgewählten Modellnamen (whitespace-getrennt, gequotet) auf stdout aus
select_models_checklist_dialog() {
    local dialog_args=()
    local i
    for i in "${!RECOMMENDED_MODELS[@]}"; do
        dialog_args+=("${RECOMMENDED_MODELS[$i]}" "${RECOMMENDED_DESCS[$i]}" "off")
    done

    local result
    result=$(dialog --stdout --clear --backtitle "Ollama Docker Setup" \
        --title "Empfohlene Modelle" \
        --checklist "Wähle die zu installierenden Modelle aus (Leertaste = auswählen, Enter = bestätigen):" 20 76 12 \
        "${dialog_args[@]}")
    local status=$?
    clear

    [ $status -ne 0 ] && return 1
    echo "$result"
    return 0
}

# Funktion zum Auswählen mehrerer Modelle per Text-Menü (Fallback ohne dialog)
# Erwartet, dass RECOMMENDED_MODELS/RECOMMENDED_DESCS bereits befüllt sind
# Gibt die ausgewählten Modellnamen zeilenweise auf stdout aus
select_models_plain_checklist() {
    echo "" >&2
    echo "Empfohlene Modelle für dein System:" >&2
    local i
    for i in "${!RECOMMENDED_MODELS[@]}"; do
        printf "  %d) %-30s %s\n" "$((i + 1))" "${RECOMMENDED_MODELS[$i]}" "${RECOMMENDED_DESCS[$i]}" >&2
    done
    echo "" >&2

    local selections
    read -p "Nummern der zu installierenden Modelle (z.B. 1 3 4), Enter für keine: " -a selections

    local idx
    for idx in "${selections[@]}"; do
        if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#RECOMMENDED_MODELS[@]}" ]; then
            echo "${RECOMMENDED_MODELS[$((idx - 1))]}"
        fi
    done
}

# Funktion zum Installieren einer Liste ausgewählter Modelle
install_chosen_models() {
    local models=("$@")

    if [ "${#models[@]}" -eq 0 ]; then
        print_info "Keine Modelle ausgewählt."
        return 0
    fi

    if ! docker ps | grep -q "ollama"; then
        print_warning "Ollama-Container läuft nicht"
        print_info "Starte erst die Container (Menüpunkt 'Container starten')"
        return 1
    fi

    local model
    for model in "${models[@]}"; do
        if model_is_installed "$model"; then
            print_warning "Modell '$model' ist bereits installiert"
            if confirm_reinstall "$model"; then
                print_info "Entferne bestehendes Modell '$model'..."
                docker exec ollama ollama rm "$model" >/dev/null 2>&1
                print_success "Altes Modell entfernt"
            else
                print_info "Überspringe '$model' (bereits installiert)"
                echo ""
                continue
            fi
        fi

        echo ""
        print_info "Installiere Modell: $model"
        print_warning "Dies kann einige Minuten dauern..."
        echo ""

        if docker exec ollama ollama pull "$model"; then
            print_success "Modell '$model' erfolgreich installiert!"
        else
            print_error "Fehler beim Installieren von '$model'"
        fi
        echo ""
    done
}

# Funktion zum Anzeigen der System-Analyse mit anschließender Checkbox-Modellauswahl
analyze_system_and_select_models() {
    analyze_system
    echo ""
    show_personalized_recommendations

    local gpu_vram_mb
    local gpu_vram_gb=0
    if command_exists nvidia-smi; then
        gpu_vram_mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
        gpu_vram_gb=$((gpu_vram_mb / 1024))
    fi
    get_recommended_models "$gpu_vram_gb"

    read -p "Möchtest du jetzt Modelle aus den Empfehlungen auswählen und installieren? (j/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[JjYy]$ ]]; then
        return 0
    fi

    local selected_models=()
    if [ "$DIALOG_BIN" = "dialog" ]; then
        local raw
        raw=$(select_models_checklist_dialog)
        if [ $? -eq 0 ] && [ -n "$raw" ]; then
            eval "selected_models=($raw)"
        fi
    else
        mapfile -t selected_models < <(select_models_plain_checklist)
    fi

    echo ""
    install_chosen_models "${selected_models[@]}"
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
    echo "3) GPU-Treiber Diagnose & Reparatur"
    echo "4) Fehlende Komponenten installieren (automatisch)"
    echo "5) Festplattenplatz prüfen"
    echo "6) Container starten"
    echo "7) GPU-Zugriff verifizieren"
    echo "8) Laufende Container anzeigen"
    echo "9) Open WebUI im Browser öffnen"
    echo "10) Installierte Modelle (Details)"
    echo "11) Modelle installieren"
    echo "12) Vollständiges Setup (Prüfen + Installieren + Starten)"
    echo "13) Beenden"
    echo ""
}

# Funktion zum Sicherstellen, dass 'dialog' (ncurses) für das Menü verfügbar ist
ensure_dialog() {
    if command_exists dialog; then
        DIALOG_BIN="dialog"
        return 0
    fi

    print_warning "'dialog' (ncurses) ist nicht installiert - wird für das grafische Menü benötigt"
    read -p "'dialog' jetzt installieren? (j/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[JjYy]$ ]]; then
        sudo apt-get update && sudo apt-get install -y dialog
        if command_exists dialog; then
            DIALOG_BIN="dialog"
            return 0
        fi
    fi

    print_info "Verwende einfaches Text-Menü"
    DIALOG_BIN=""
    return 1
}

# Hauptmenü als ncurses-Dialog (dialog). Gibt die gewählte Option auf stdout aus.
show_menu_dialog() {
    dialog --stdout --clear --backtitle "Ollama Docker Setup" \
        --title "Hauptmenü" \
        --menu "Wähle eine Option (Pfeiltasten + Enter, ESC zum Beenden):" 24 72 13 \
        1  "System-Analyse & Modell-Empfehlungen" \
        2  "Alle Voraussetzungen prüfen" \
        3  "GPU-Treiber Diagnose & Reparatur" \
        4  "Fehlende Komponenten installieren (automatisch)" \
        5  "Festplattenplatz prüfen" \
        6  "Container starten" \
        7  "GPU-Zugriff verifizieren" \
        8  "Laufende Container anzeigen" \
        9  "Open WebUI im Browser öffnen" \
        10 "Installierte Modelle (Details)" \
        11 "Modelle installieren" \
        12 "Vollständiges Setup (Prüfen + Installieren + Starten)" \
        13 "Beenden"
}

# Funktion zum Prüfen aller Voraussetzungen
check_all_prerequisites() {
    local all_ok=true

    if ! check_nvidia_gpu; then
        all_ok=false
    fi
    echo ""

    if ! check_nvidia_kernel_module; then
        all_ok=false
    fi
    echo ""

    if ! check_nvidia_driver_conflicts; then
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
        print_info "Bei GPU/Treiber-Problemen: Menüpunkt 'GPU-Treiber Diagnose & Reparatur'"
        print_info "Bei fehlendem Docker/Toolkit: Menüpunkt 'Fehlende Komponenten installieren (automatisch)'"
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
        ensure_dialog
        while true; do
            local choice=""
            if [ "$DIALOG_BIN" = "dialog" ]; then
                choice=$(show_menu_dialog)
                local dialog_status=$?
                clear
                if [ $dialog_status -ne 0 ]; then
                    choice=13
                fi
            else
                show_menu
                read -p "Wähle eine Option: " choice
            fi

            case $choice in
                1)
                    clear
                    analyze_system_and_select_models
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
                    fix_nvidia_gpu
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                4)
                    clear
                    auto_install
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                5)
                    clear
                    check_storage
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                6)
                    clear
                    create_directories
                    start_containers
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                7)
                    clear
                    verify_gpu_access
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                8)
                    clear
                    show_running_containers
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                9)
                    clear
                    open_browser "http://localhost:3000"
                    sleep 2
                    clear
                    ;;
                10)
                    clear
                    check_installed_models
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                11)
                    clear
                    install_models
                    clear
                    ;;
                12)
                    clear
                    full_setup
                    read -p "Drücke Enter zum Fortfahren..."
                    clear
                    ;;
                13)
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
