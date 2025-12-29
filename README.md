# Ollama Docker Setup mit GPU-Unterstützung

Dieses Projekt bietet ein vollständiges Setup für Ollama mit GPU-Beschleunigung (NVIDIA) und Open WebUI als Frontend.

## Überblick

- **Ollama**: Lokal laufende LLM-Engine mit GPU-Unterstützung
- **Open WebUI**: Benutzerfreundliches Web-Interface für Ollama
- **GPU**: NVIDIA RTX A3000 Laptop GPU (oder kompatible NVIDIA-GPU)

## Voraussetzungen

### Hardware
- NVIDIA GPU (getestet mit RTX A3000)
- Mindestens 6 GB VRAM empfohlen

### Software
- Ubuntu/Linux mit NVIDIA-Treibern installiert
- Docker und Docker Compose
- NVIDIA Container Toolkit

## Installation & Konfiguration

### 1. NVIDIA-Treiber prüfen

Stelle sicher, dass die NVIDIA-Treiber funktionieren:

```bash
nvidia-smi
```

Du solltest deine GPU und die Treiberversion sehen.

### 2. NVIDIA Container Toolkit installieren

Falls noch nicht installiert:

```bash
# Distribution und Architektur setzen
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Installieren
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
```

Prüfen, ob es installiert ist:

```bash
dpkg -l | grep -i nvidia-container
```

### 3. Docker für NVIDIA Runtime konfigurieren

**Wichtig**: Dies ist der kritische Schritt, der oft fehlt!

Erstelle/Bearbeite die Docker Daemon-Konfiguration:

```bash
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
```

Docker-Daemon neu starten:

```bash
sudo systemctl restart docker
```

### 4. Container starten

```bash
docker compose up -d
```

### 5. GPU-Zugriff verifizieren

Prüfe, ob Ollama die GPU erkennt:

```bash
docker exec ollama nvidia-smi
```

## Verwendung

### Web-Interface (Open WebUI)

Öffne im Browser: **http://localhost:3000**

Hier kannst du:
- Modelle über die UI verwalten
- Mit den Modellen chatten
- Konversationen speichern

### Kommandozeile (CLI)

#### Modell herunterladen

```bash
docker exec ollama ollama pull llama3.2:3b
```

Weitere beliebte Modelle:
- `llama3.2:1b` - Sehr klein und schnell (1.3 GB)
- `llama3.2:3b` - Klein, gute Performance (2 GB)
- `mistral:7b` - Mittlere Größe (4.1 GB)
- `llama2:13b` - Größer, bessere Qualität (7.4 GB)

#### Modell direkt verwenden

```bash
docker exec ollama ollama run llama3.2:3b "Deine Frage hier"
```

#### Verfügbare Modelle anzeigen

```bash
docker exec ollama ollama list
```

#### Modell löschen

```bash
docker exec ollama ollama rm llama3.2:3b
```

### GPU-Auslastung überwachen

Während ein Modell läuft:

```bash
watch -n 1 nvidia-smi
```

Du solltest sehen:
- GPU-Auslastung bei ~90%+
- GPU-Speicher wird von `/usr/bin/ollama` verwendet
- Höhere GPU-Temperatur während Inferenz

## Projektstruktur

```
.
├── docker-compose.yml          # Docker Compose Konfiguration
├── README.md                   # Diese Datei
└── /home/julian/ollama/        # Ollama Modelle und Daten
    └── /home/julian/open-webui/  # Open WebUI Daten
```

## docker-compose.yml Erklärung

```yaml
services:
  ollama:
    image: ollama/ollama
    container_name: ollama
    volumes:
      - /home/julian/ollama:/root/.ollama  # Modelle persistent speichern
    ports:
      - "11434:11434"  # Ollama API Port
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia      # NVIDIA GPU-Treiber
              count: all          # Alle verfügbaren GPUs nutzen
              capabilities: [gpu] # GPU-Capabilities aktivieren
    restart: unless-stopped

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    volumes:
      - /home/julian/open-webui:/app/backend/data  # Daten persistent
    ports:
      - "3000:8080"  # WebUI auf Port 3000
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434  # Verbindung zu Ollama
    depends_on:
      - ollama
    restart: unless-stopped
```

## Troubleshooting

### Problem: "could not select device driver 'nvidia' with capabilities: [[gpu]]"

**Lösung**: Docker-Daemon-Konfiguration fehlt (siehe Schritt 3)

1. Erstelle `/etc/docker/daemon.json` mit NVIDIA Runtime-Konfiguration
2. Starte Docker neu: `sudo systemctl restart docker`
3. Starte Container neu: `docker compose up -d`

### Problem: Modell lädt sehr langsam

**Ursache**: GPU wird nicht verwendet

**Prüfen**:
```bash
docker exec ollama nvidia-smi
```

Sollte die GPU und Ollama-Prozess zeigen.

### Problem: Container startet nicht

**Logs anschauen**:
```bash
docker compose logs ollama
docker compose logs open-webui
```

### Problem: Open WebUI kann sich nicht zu Ollama verbinden

**Prüfen**:
1. Ist Ollama erreichbar?
   ```bash
   curl http://localhost:11434
   ```
2. Sind beide Container im gleichen Netzwerk?
   ```bash
   docker network inspect ollama-docker-w-gpu_default
   ```

## Nützliche Befehle

### Container-Status prüfen

```bash
docker compose ps
```

### Container-Logs anschauen

```bash
docker compose logs -f ollama
docker compose logs -f open-webui
```

### Container stoppen

```bash
docker compose down
```

### Container stoppen und Volumes löschen

```bash
docker compose down -v
```

### In Container-Shell einsteigen

```bash
docker exec -it ollama /bin/bash
```

### Speicherplatz von Modellen prüfen

```bash
du -sh /home/julian/ollama/
```

## Leistung

Mit GPU-Beschleunigung (NVIDIA RTX A3000):
- **GPU-Auslastung**: 90-95% während Inferenz
- **GPU-Speicher**: ~2 GB für llama3.2:3b
- **Inferenz-Geschwindigkeit**: Deutlich schneller als CPU-only

Ohne GPU (CPU-only) wäre die Inferenz deutlich langsamer.

## Ports

- **3000**: Open WebUI (Web-Interface)
- **11434**: Ollama API

## Volumes (Datenpersistenz)

- `/home/julian/ollama`: Ollama-Modelle und Konfiguration
- `/home/julian/open-webui`: Open WebUI Daten und Chat-Verläufe

## Sicherheit

- Die Container sind nur auf `localhost` erreichbar
- Für produktiven Einsatz sollte ein Reverse-Proxy (nginx) mit HTTPS verwendet werden
- Authentifizierung ist standardmäßig aktiviert in Open WebUI

## Weiterführende Links

- [Ollama Dokumentation](https://github.com/ollama/ollama)
- [Open WebUI Dokumentation](https://github.com/open-webui/open-webui)
- [Ollama Modellbibliothek](https://ollama.ai/library)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)

## Lizenz

Dieses Setup basiert auf Open-Source-Software:
- Ollama: MIT License
- Open WebUI: MIT License
