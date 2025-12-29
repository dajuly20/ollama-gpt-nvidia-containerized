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

**Uncensored Modelle** (weniger Content-Filtering):
- `dolphin-mistral:7b-v2.6` - Ausgewogen, vielseitig (4.1 GB) - **Empfohlen**
- `nous-hermes2:latest` - Exzellent für Reasoning (6.1 GB)
- `wizard-vicuna-uncensored:13b` - Ohne Safety-Filter (7.4 GB)
- `openchat:7b` - Guter Kompromiss (4.1 GB)

**Hinweis zu Uncensored Modellen:**
- Haben weniger Sicherheitsfilter als Standard-Modelle
- Können offener auf verschiedene Themen antworten
- Keine Garantie für Qualität oder Faktentreue
- Verantwortungsvolle Nutzung liegt beim User
- Siehe Abschnitt "Uncensored Modelle" unten für Details

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

## Modellübersicht und Systemanforderungen

Diese Tabelle zeigt die wichtigsten Modelle mit ihren Hardware-Anforderungen.

### Kleine Modelle (1-3B Parameter)

| Modell | Größe | VRAM (GPU) | RAM (CPU-only) | Geschwindigkeit | Qualität | Use-Case |
|--------|-------|------------|----------------|-----------------|----------|----------|
| `llama3.2:1b` | 1.3 GB | 2 GB | 4 GB | ⚡⚡⚡⚡⚡ Sehr schnell | ⭐⭐⭐ Gut | Einfache Aufgaben, Embedded |
| `llama3.2:3b` | 2.0 GB | 3 GB | 6 GB | ⚡⚡⚡⚡ Schnell | ⭐⭐⭐⭐ Sehr gut | Alltag, Chat, Code |
| `phi3:mini` | 2.3 GB | 3 GB | 6 GB | ⚡⚡⚡⚡ Schnell | ⭐⭐⭐⭐ Sehr gut | Reasoning, Math |
| `qwen2.5:3b` | 2.0 GB | 3 GB | 6 GB | ⚡⚡⚡⚡ Schnell | ⭐⭐⭐⭐ Sehr gut | Mehrsprachig, Code |

### Mittlere Modelle (7-8B Parameter) - Empfohlen für RTX A3000

| Modell | Größe | VRAM (GPU) | RAM (CPU-only) | Geschwindigkeit | Qualität | Use-Case |
|--------|-------|------------|----------------|-----------------|----------|----------|
| `mistral:7b` | 4.1 GB | 5 GB | 10 GB | ⚡⚡⚡ Mittel | ⭐⭐⭐⭐⭐ Exzellent | Allround, sehr gut |
| `llama3.1:8b` | 4.7 GB | 6 GB | 12 GB | ⚡⚡⚡ Mittel | ⭐⭐⭐⭐⭐ Exzellent | Reasoning, Chat |
| `dolphin-mistral:7b` | 4.1 GB | 5 GB | 10 GB | ⚡⚡⚡ Mittel | ⭐⭐⭐⭐ Sehr gut | **Uncensored**, Code |
| `openchat:7b` | 4.1 GB | 5 GB | 10 GB | ⚡⚡⚡ Mittel | ⭐⭐⭐⭐ Sehr gut | Chat, hilfreich |
| `gemma2:9b` | 5.5 GB | 6 GB | 14 GB | ⚡⚡⚡ Mittel | ⭐⭐⭐⭐⭐ Exzellent | Von Google, sehr gut |

### Große Modelle (13B+ Parameter) - Knapp/Zu groß für 6GB VRAM

| Modell | Größe | VRAM (GPU) | RAM (CPU-only) | Geschwindigkeit | Qualität | Use-Case |
|--------|-------|------------|----------------|-----------------|----------|----------|
| `llama2:13b` | 7.4 GB | 8 GB | 16 GB | ⚡⚡ Langsam | ⭐⭐⭐⭐⭐ Exzellent | Komplexe Aufgaben |
| `nous-hermes2` | 6.1 GB | 6 GB | 14 GB | ⚡⚡ Langsam | ⭐⭐⭐⭐⭐ Exzellent | **Uncensored**, Reasoning |
| `codellama:13b` | 7.4 GB | 8 GB | 16 GB | ⚡⚡ Langsam | ⭐⭐⭐⭐⭐ Exzellent | Code-Generierung |
| `mixtral:8x7b` | 26 GB | 28 GB | 48 GB | ⚡ Sehr langsam | ⭐⭐⭐⭐⭐ Top | **Zu groß** für RTX A3000 |

### Spezial-Modelle

| Modell | Größe | VRAM (GPU) | RAM (CPU-only) | Besonderheit |
|--------|-------|------------|----------------|--------------|
| `codellama:7b` | 4.1 GB | 5 GB | 10 GB | Code-Generierung |
| `deepseek-coder:6.7b` | 3.8 GB | 5 GB | 10 GB | Code, sehr gut |
| `starcoder2:7b` | 4.0 GB | 5 GB | 10 GB | Code, von HuggingFace |
| `nomic-embed-text` | 274 MB | 1 GB | 2 GB | Text-Embeddings (für RAG) |
| `llava:7b` | 4.5 GB | 6 GB | 12 GB | **Multimodal** (Bild + Text) |

### Empfehlungen für deine RTX A3000 (6 GB VRAM)

#### Perfekt (läuft problemlos):
- ✅ Alle 1-3B Modelle (llama3.2:1b, llama3.2:3b, phi3:mini)
- ✅ Alle 7-8B Modelle (mistral:7b, llama3.1:8b, dolphin-mistral:7b)
- ✅ `gemma2:9b` (läuft noch, kann knapp werden)

#### Knapp (funktioniert, kann eng werden):
- ⚠️ `nous-hermes2` (6.1 GB) - Läuft, aber nutzt fast gesamtes VRAM
- ⚠️ `llava:7b` (Multimodal) - Kann knapp werden

#### Zu groß (Out of Memory):
- ❌ Alle 13B+ Modelle (llama2:13b, codellama:13b, etc.)
- ❌ `mixtral:8x7b` und größer

### CPU vs GPU Performance

**Mit GPU (RTX A3000):**
- 7B Modell: ~30-50 Tokens/Sekunde
- 3B Modell: ~60-100 Tokens/Sekunde
- GPU-Auslastung: 90-95%

**Ohne GPU (CPU-only):**
- 7B Modell: ~3-8 Tokens/Sekunde
- 3B Modell: ~10-15 Tokens/Sekunde
- CPU-Auslastung: 100% auf allen Kernen

**Fazit:** GPU ist ~10x schneller!

### Modellauswahl - Entscheidungshilfe

```
Brauchst du maximale Geschwindigkeit?
  → llama3.2:1b oder llama3.2:3b

Brauchst du beste Qualität (bei 6GB)?
  → mistral:7b oder llama3.1:8b

Brauchst du Code-Generierung?
  → deepseek-coder:6.7b oder codellama:7b

Brauchst du Uncensored?
  → dolphin-mistral:7b-v2.6 (empfohlen)
  → nous-hermes2 (für komplexe Aufgaben)

Brauchst du Multimodal (Bilder)?
  → llava:7b (Bild + Text verstehen)

Budget-PC ohne GPU?
  → llama3.2:3b oder phi3:mini (klein, effizient)
```

### Quantisierung verstehen

Ollama lädt standardmäßig **4-bit quantisierte** Modelle (Q4_0).

**Was bedeutet das?**
- Original-Modell: 32-bit oder 16-bit Präzision
- Q4_0: 4-bit Präzision (8x kleiner!)
- Qualitätsverlust: Minimal (~1-3%)
- VRAM-Ersparnis: Massiv

**Beispiel:**
- Llama 3.1 8B (Original): ~32 GB
- Llama 3.1 8B (Q4_0): ~4.7 GB

**Andere Quantisierungen in Ollama:**
```bash
# Höhere Qualität, mehr VRAM
docker exec ollama ollama pull llama3.1:8b-instruct-q8_0  # 8-bit

# Standard (empfohlen)
docker exec ollama ollama pull llama3.1:8b  # 4-bit (Q4_0)

# Kleinere Größe, geringere Qualität
docker exec ollama ollama pull llama3.1:8b-instruct-q2_k  # 2-bit
```

**Empfehlung:** Bleib bei Q4_0 (Standard) - beste Balance!

## Text-to-Speech (TTS) Konfiguration

Open WebUI unterstützt verschiedene TTS-Engines für das Vorlesen von Antworten.

### Option 1: Web Speech API (Browser-basiert, kostenlos)

Die einfachste Lösung - nutzt die TTS-Engine deines Browsers.

**Setup:**
1. Öffne **http://localhost:3000**
2. Klicke auf dein **Profil-Icon** (oben rechts)
3. Gehe zu **Settings** → **Audio**
4. Bei **Text-to-Speech**:
   - Aktiviere TTS
   - Wähle **Web API** als Engine
   - Unter **Voice** kannst du verschiedene Stimmen auswählen

**Verfügbare Stimmen** (je nach Browser):
- **Deutsch**: "Google Deutsch", "Microsoft Hedda", "Microsoft Katja"
- **English**: "Google US English", "Google UK English", "Microsoft Mark", "Microsoft Zira"

**Problem: Deutsche Stimme klingt komisch bei englischem Text**

Wenn eine deutsche Stimme englischen Text vorliest, klingt es wie "Denglisch" - die Aussprache ist nicht nativ. Du musst die Stimme manuell umschalten:

- Für **englische Texte**: Wähle eine englische Stimme (z.B. "Google US English")
- Für **deutsche Texte**: Wähle eine deutsche Stimme (z.B. "Google Deutsch")

**Nachteil**: Manuelle Umstellung bei Sprachwechsel notwendig.

### Option 2: OpenAI TTS (Beste Qualität, automatisch mehrsprachig)

OpenAI's TTS-Modelle erkennen automatisch die Sprache und sprechen **Deutsch UND Englisch perfekt** aus - ohne manuelle Umstellung!

**Setup:**

1. Erstelle einen OpenAI API Key:
   - Gehe zu [platform.openai.com](https://platform.openai.com)
   - Erstelle einen Account (falls noch nicht vorhanden)
   - Navigiere zu **API Keys** und erstelle einen neuen Key

2. Konfiguriere in Open WebUI:
   - **Settings** → **Audio** → **Text-to-Speech**
   - **TTS Engine**: `OpenAI`
   - **API Base URL**: `https://api.openai.com/v1`
   - **API Key**: Dein OpenAI API Key einfügen
   - **Model**:
     - `tts-1` - Schneller, gut für Echtzeit
     - `tts-1-hd` - Höhere Qualität (empfohlen)
   - **Voice**: Wähle eine Stimme:
     - `alloy` - Neutral, ausgewogen
     - `echo` - Männlich, klar
     - `fable` - Britischer Akzent
     - `onyx` - Männlich, tief
     - `nova` - Weiblich, warm
     - `shimmer` - Weiblich, energisch

**Vorteile:**
- ✅ Automatische Spracherkennung (Deutsch + Englisch)
- ✅ Sehr natürliche Aussprache
- ✅ Keine manuelle Umstellung notwendig
- ✅ Konsistente Qualität

**Kosten:**
- ~$15.00 pro 1 Million Zeichen
- Beispiel: 1000 Zeichen = ca. $0.015 (sehr günstig)
- Für normalen Gebrauch: wenige Euro pro Monat

### Option 3: Piper (Lokal, Open Source, kostenlos)

Piper ist eine lokale, offline TTS-Engine mit guter Qualität.

**Setup:**

```bash
# Piper Docker Container starten
docker run -d \
  --name piper \
  --restart unless-stopped \
  -p 10200:10200 \
  rhasspy/wyoming-piper:latest
```

**In Open WebUI konfigurieren:**
- **Settings** → **Audio** → **Text-to-Speech**
- **TTS Engine**: `OpenAI` (Piper nutzt kompatible API)
- **API Base URL**: `http://localhost:10200`
- Wähle ein Modell/Voice für deine Sprache

**Vorteile:**
- ✅ Komplett offline
- ✅ Kostenlos
- ✅ Datenschutz (keine externen APIs)

**Nachteile:**
- ⚠️ Qualität geringer als OpenAI TTS
- ⚠️ Manueller Sprachwechsel notwendig

### Option 4: Coqui TTS (Lokal, mit GPU-Beschleunigung)

Für beste lokale Qualität mit GPU-Unterstützung.

**Setup:**

```bash
# Coqui TTS mit GPU-Unterstützung
docker run -d \
  --name coqui-tts \
  --restart unless-stopped \
  --gpus all \
  -p 5002:5002 \
  ghcr.io/coqui-ai/tts
```

**In Open WebUI konfigurieren:**
- **Settings** → **Audio** → **Text-to-Speech**
- **TTS Engine**: Custom
- **API URL**: `http://localhost:5002`

**Vorteile:**
- ✅ Sehr gute Qualität
- ✅ GPU-beschleunigt (schnell)
- ✅ Mehrsprachig
- ✅ Kostenlos und Open Source

### Spracheinstellungen für LLM-Modelle

Die **Antwortsprache** der LLMs steuerst du über Prompts:

**Im Terminal:**
```bash
# Auf Deutsch
docker exec ollama ollama run dolphin-mistral:7b-v2.6 "Antworte auf Deutsch: Erkläre Quantencomputing"

# Auf Englisch
docker exec ollama ollama run dolphin-mistral:7b-v2.6 "Answer in English: Explain quantum computing"
```

**Im Web UI - System Prompt setzen:**
1. Klicke auf das **Modell-Dropdown** (oben)
2. Wähle **Customize** oder klicke auf das Zahnrad-Icon
3. Setze einen **System Prompt**:
   - Deutsch: `Du antwortest immer auf Deutsch und bist hilfsbereit.`
   - English: `You always answer in English and are helpful.`

**Pro-Tipp:** Die meisten Modelle erkennen automatisch die Sprache deiner Frage und antworten entsprechend!

### TTS-Empfehlung

| Priorität | Engine | Vorteile | Nachteile | Für wen? |
|-----------|--------|----------|-----------|----------|
| 🥇 **1** | **OpenAI TTS** | Beste Qualität, automatisch mehrsprachig | Kostet wenig Geld, benötigt API Key | **Empfohlen für alle** |
| 🥈 **2** | **Web Speech API** | Kostenlos, keine Setup | Manuelle Stimmenwahl, Browser-abhängig | Gelegenheitsnutzer |
| 🥉 **3** | **Coqui TTS** | Lokal, GPU-beschleunigt, gute Qualität | Setup aufwändiger | Datenschutz-bewusste User |
| **4** | **Piper** | Einfach, offline | Geringere Qualität | Offline-Nutzung |

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

## Uncensored Modelle

"Uncensored" oder "Unfiltered" Modelle sind LLMs, bei denen die Sicherheitsfilter reduziert oder entfernt wurden.

### Was bedeutet "Uncensored"?

Standard-Modelle wie Llama 2/3, GPT, Claude etc. durchlaufen ein **Alignment-Training**, das:
- Ablehnung von bestimmten Anfragen einbaut ("I cannot assist with...")
- Sicherheitsrichtlinien durchsetzt
- Potenziell schädliche Ausgaben filtert

Uncensored Modelle:
- Haben dieses Safety-Training teilweise oder komplett übersprungen
- Antworten freier auf verschiedene Themen
- Lehnen weniger Anfragen ab

### Empfohlene Uncensored Modelle

#### 1. Dolphin-Mistral 7B (Empfohlen für Einsteiger)

```bash
docker exec ollama ollama pull dolphin-mistral:7b-v2.6
```

**Specs:**
- Größe: 4.1 GB
- Basis: Mistral 7B
- VRAM: ~4-5 GB
- Creator: Eric Hartford

**Besonderheiten:**
- Entfernte Alignment-Layer von Mistral
- Ausgewogen zwischen Freiheit und Nützlichkeit
- Sehr vielseitig einsetzbar
- Gute Code-Generation
- **Beste Wahl für die meisten Use-Cases**

#### 2. Nous-Hermes 2

```bash
docker exec ollama ollama pull nous-hermes2:latest
```

**Specs:**
- Größe: 6.1 GB
- Basis: Mistral/Mixtral
- VRAM: ~5-6 GB
- Creator: Nous Research

**Besonderheiten:**
- Fokus auf Reasoning und komplexe Aufgaben
- Exzellente Instruktionsbefolgung
- Weniger restriktiv als Standard-Modelle
- **Beste Wahl für komplexe Problemlösungen**

#### 3. WizardVicuna Uncensored 13B

```bash
docker exec ollama ollama pull wizard-vicuna-uncensored:13b
```

**Specs:**
- Größe: 7.4 GB
- VRAM: ~7-8 GB (kann knapp werden bei 6 GB VRAM!)
- Basis: Vicuna 13B

**Warnung:** Könnte bei 6 GB VRAM zu Problemen führen - verwende lieber 7B Modelle!

### Hardware-Anforderungen für deine RTX A3000 (6 GB VRAM)

| Modell | Größe | VRAM benötigt | Passt? | Empfehlung |
|--------|-------|---------------|--------|------------|
| dolphin-mistral:7b | 4.1 GB | ~4-5 GB | ✅ Ja | **Perfekt** |
| nous-hermes2 | 6.1 GB | ~5-6 GB | ✅ Knapp | **Funktioniert** |
| wizard-vicuna:13b | 7.4 GB | ~7-8 GB | ❌ Nein | Zu groß |
| openchat:7b | 4.1 GB | ~4-5 GB | ✅ Ja | Gut |

### Verwendung

**CLI:**
```bash
# Dolphin-Mistral
docker exec ollama ollama run dolphin-mistral:7b-v2.6 "Write a Python function to..."

# Nous-Hermes
docker exec ollama ollama run nous-hermes2 "Explain the difference between..."
```

**Web UI:**
- Öffne http://localhost:3000
- Wähle das Modell im Dropdown oben links
- Chatte wie gewohnt

### Wichtige Hinweise

**Was Uncensored NICHT bedeutet:**
- ❌ "Perfekte" oder "wahre" Antworten
- ❌ Keine technischen Grenzen
- ❌ Immer besser als gefilterte Modelle
- ❌ Garantie für ethisch vertretbare Ausgaben

**Was Uncensored bedeutet:**
- ✅ Weniger Ablehnungen bei Anfragen
- ✅ Offenere Diskussionen über verschiedene Themen
- ✅ Weniger "Ich kann dabei nicht helfen"-Antworten
- ✅ Mehr Kontrolle über den Output

**Verantwortung:**
- Du bist verantwortlich für die Nutzung
- Illegale Aktivitäten bleiben illegal, egal welches Modell
- Diese Modelle können auch "halluzinieren" (falsche Infos erfinden)
- Kritisch prüfen, nicht blind vertrauen

### Qualität: Uncensored vs. Standard

**Vorteile von Uncensored:**
- Weniger Beschränkungen
- Kreativere Antworten möglich
- Bessere Code-Generierung (oft weniger vorsichtig)
- Direkte Antworten ohne Umschweife

**Nachteile:**
- Können manchmal zu "freizügig" antworten
- Weniger Safety-Checks können zu problematischen Outputs führen
- Manchmal weniger "hilfreich" als Standard-Modelle
- Halluzinationen können häufiger sein

### Vergleich: Standard vs. Uncensored

```bash
# Standard-Modell (z.B. llama3.2)
Frage: "How can I hack a website?"
Antwort: "I cannot provide assistance with hacking or unauthorized access..."

# Uncensored-Modell (z.B. dolphin-mistral)
Frage: "How can I hack a website?"
Antwort: "There are various penetration testing techniques used by security professionals..."
(Erklärt legitime Pentesting-Methoden)
```

### Best Practices

1. **Nutze Uncensored für:**
   - Creative Writing ohne Einschränkungen
   - Code-Generierung
   - Technische/wissenschaftliche Diskussionen
   - Rollenspiele / Storytelling
   - Pentesting / Security Research (legal!)

2. **Nutze Standard-Modelle für:**
   - Allgemeine Fragen
   - Wenn du "sichere" Antworten bevorzugst
   - Professionelle/geschäftliche Nutzung
   - Wenn Compliance wichtig ist

3. **Vergleiche beide:**
   - Teste die gleiche Frage mit beiden Typen
   - Nutze das Modell, das für deinen Use-Case besser passt

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
