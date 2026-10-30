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

## Modell benutzen

**Web:** http://localhost:3000 öffnen → Modell oben auswählen → chatten.

**CLI:**
```bash
docker exec -it ollama ollama run llama3.1:8b "Hallo, wie geht's?"
docker exec ollama ollama pull <modell>     # neues Modell holen, z.B. llama3.2:3b
```

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
