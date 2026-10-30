# START — Ollama GPU-Stack (RTX A3000)

Schnellstart-/Betriebsanleitung für den **konsolidierten** Stack. Das einmalige Setup
(NVIDIA-Treiber, Container-Toolkit, Stack-Konsolidierung) ist bereits erledigt — siehe
`~/BashScripts/claudeProjects/ollama-gpu-stack/CLAUDE.md`. Tiefergehende Infos (Modelle, TTS,
uncensored, Troubleshooting) stehen im großen `README.md`.

## Stack starten

```bash
cd ~/docker-stacks-home/ollama-docker-w-gpu
docker compose up -d
```

Das startet zwei Container:

| Container | Dienst | URL / Port |
|---|---|---|
| `ollama` | LLM-Engine (GPU) | http://localhost:11434 |
| `open-webui` | Web-Frontend | **http://localhost:3000** |

Beide haben `restart: unless-stopped` → starten nach einem Reboot automatisch wieder.

## Status & GPU prüfen

```bash
docker compose ps                       # laufen beide Container?
docker exec ollama nvidia-smi           # sieht der Container die GPU?
docker exec ollama ollama list          # welche Modelle sind da?
docker exec ollama ollama ps            # laeuft ein Modell auf GPU? (Spalte PROCESSOR)
```

`ollama ps` sollte bei einem aktiven Modell z. B. `7%/93% CPU/GPU` zeigen — d. h. es rechnet
überwiegend auf der GPU. (Bei einem 8B-Modell + Context auf 6 GB VRAM bleibt ein kleiner CPU-Rest,
das ist normal.)

## Modelle installieren

Modelle werden in den laufenden `ollama`-Container geladen und landen automatisch unter
`/home/julian/ollama` (bleiben also bei Neustart/`down` erhalten). Namen + Tags findest du auf
<https://ollama.com/library>.

**Variante A — CLI (empfohlen):**
```bash
docker exec ollama ollama pull llama3.2:3b     # Modell herunterladen
docker exec ollama ollama list                 # installierte Modelle anzeigen
docker exec ollama ollama rm <modell>          # Modell wieder löschen
```

**Variante B — Web-UI:** http://localhost:3000 → oben links aufs Modell-Dropdown → Namen
eintippen (z. B. `llama3.2:3b`) → „Pull `<modell>`" anklicken. Lädt im Hintergrund.

**Variante C — direkt per API:**
```bash
curl http://localhost:11434/api/pull -d '{"name":"llama3.2:3b"}'
```

### Empfohlene Modelle für die RTX A3000 (6 GB VRAM)

Faustregel: Q4-quantisierte Modelle bis ~8B passen gut; alles bis ~5–6 GB läuft (fast) komplett
auf der GPU, größere Modelle teilen sich CPU/GPU und werden langsamer.

| Modell | Größe | Zweck |
|---|---|---|
| `llama3.2:3b` | ~2 GB | schnell, Alltag, läuft 100 % auf GPU |
| `llama3.1:8b` | ~4.9 GB | guter Allrounder (bereits installiert), ~93 % GPU |
| `qwen2.5:7b` | ~4.7 GB | stark bei Code/Reasoning |
| `gemma2:2b` | ~1.6 GB | sehr schnell, wenig VRAM |
| `nomic-embed-text` | ~0.3 GB | Embeddings (RAG/Dokumente in Open WebUI) |

Nach dem Pull taucht das Modell sofort im WebUI-Dropdown auf. Testen:
```bash
docker exec -it ollama ollama run llama3.2:3b "Hallo, wie geht's?"
```

> Tiefer: Modellauswahl, Quantisierung, große/uncensored Modelle → `README.md`.

### Komfort: `models`-Helfer (gollama-TUI + Hardware-Empfehlung)

Helfer-Skript `~/BashScripts/scripts/ollama-models.sh` (Alias **`models`**) bündelt alles:

```bash
models                      # gollama-TUI: installierte Modelle durchblättern/verwalten
models recommend            # schlägt ein Modell passend zu VRAM/RAM/CPU vor (portabel)
models list                 # kurze Liste ohne TUI
models pull llama3.2:3b     # Modell laden
models rm <modell>          # löschen
models run llama3.1:8b      # im Terminal chatten
models web                  # Open WebUI im Browser öffnen
```

`models recommend` erkennt die Hardware automatisch (NVIDIA-GPU → VRAM, sonst CPU/RAM) und
nennt ein passendes Modell — funktioniert also auch auf anderen Rechnern. `gollama` wird beim
ersten Start bei Bedarf via `go install` nachgezogen.

## Daten (Persistenz)

Bind-Mounts auf dem Host (bleiben bei `down`/Neustart erhalten):

- Modelle: `/home/julian/ollama`  → im Container `/root/.ollama`  (~4.6 G)
- WebUI (User, Chats, Settings): `/home/julian/open-webui` → `/app/backend/data`  (~0.9 G)

## Häufige Befehle

```bash
docker compose logs -f ollama           # Logs verfolgen
docker compose restart                  # neu starten
docker compose down                     # stoppen (Daten bleiben, da Bind-Mounts)
docker compose pull && docker compose up -d   # Images aktualisieren
```

## Wenn die GPU nach einem Reboot nicht greift

Der Laptop läuft im `prime-select on-demand`-Modus; das `nvidia`-Kernelmodul wird bei Bedarf
geladen. Falls `docker exec ollama nvidia-smi` nach einem Reboot fehlschlägt:

```bash
sudo modprobe nvidia && nvidia-smi       # Modul manuell laden
# Falls 'could not insert off': blacklist-Relikt -> einmalig:
sudo prime-select on-demand              # entfernt /lib/modprobe.d/blacklist-nvidia.conf
docker compose restart
```
