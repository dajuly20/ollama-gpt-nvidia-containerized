# CLAUDE.md — ollama-gpu-stack

Dev-/Tracking-Kontext für diesen GPU-Stack (Ollama + Open-WebUI, RTX A3000 Mobile auf dem
Precision 7560). **Diese Datei lebt jetzt direkt beim Stack** (`ollama-docker-w-gpu/`, privates
Repo `ollama-gpt-nvidia-containerized`) — zusammen mit `README.md`, `START.md`,
`docker-compose.yml`. In `~/BashScripts/claudeProjects/ollama-gpu-stack/` liegt nur noch ein
Zeiger-Stub. Helfer-Skripte liegen weiterhin in `~/BashScripts/scripts/`
(z. B. `ollama-models.sh` / Alias `models`, `claude-run-in-pane.sh`).

## Ausgangslage (Stand 2026-10-30)

**Hardware:** Precision 7560, Intel UHD (Optimus) + **NVIDIA RTX A3000 Mobile, 6 GB VRAM**.
`prime-select` = `on-demand`, Secure Boot aus, nouveau nicht geladen.

**Treiber:** Nach Cleanup nur noch `nvidia-driver-615-open` / `nvidia-dkms-615-open`;
DKMS für Kernel 7.0.0-38 gebaut. Die alten **580er** wurden entfernt via
`~/docker-stacks-home/ollama-docker-w-gpu/cleanup-580-drivers.sh`.

**4 überlappende Stacks** in `~/docker-stacks-home/` (alle `container_name: ollama`/`open-webui`,
nur einer kann laufen):
| Ordner | Modus | Ports | Status (30.10.) |
|---|---|---|---|
| `ollama/` | CPU (GPU auskommentiert) | 11434 | aus |
| `ollama-docker-w-gpu/` | **GPU** + README + install.sh | 11434, 3000 | aus → **Zielstack** |
| `ollama-opt-docker/` | CPU, Daten im Repo | 3002 | lief zuletzt (CPU) |
| `open-webui/` | nur WebUI → Host-Ollama | 3000 | aus |

**Entscheidung:** `ollama-docker-w-gpu` wird der einzige Stack; die anderen 3 werden entfernt.

## Status: ✅ ABGESCHLOSSEN (2026-10-30)

Alle 3 Phasen erledigt — GPU-Betrieb läuft. Verbleibender Stack: **nur noch
`ollama-docker-w-gpu`** (ollama :11434 + open-webui :3000), Daten unter `/home/julian/ollama`
(4.6 G Modelle) und `/home/julian/open-webui` (890 M). `llama3.1:8b` läuft zu **93 % auf der GPU**
(`ollama ps` → `7%/93% CPU/GPU`; nvidia-smi → ~5.4 G VRAM, ollama-Prozess). Der kleine CPU-Rest
ist bei 6 GB VRAM + 8B-Modell + Context erwartbar.

- [x] **Phase 1 — Treiber laden.** Ursache des `could not insert 'off'`:
      `/lib/modprobe.d/blacklist-nvidia.conf` (von `nvidia-prime` im intel-Modus erzeugt,
      enthielt `blacklist nvidia` + `alias nvidia off`) — ein veraltetes Relikt, obwohl
      `prime-select query` = `on-demand`. **Fix:** `sudo prime-select on-demand` neu ausgeführt →
      `_disable_nvidia(keep_nvidia_modules=True)` löscht die blacklist-Datei + baut initramfs neu.
      Danach `modprobe nvidia` + `nvidia-smi` OK (RTX A3000, Treiber 615.71.09, CUDA 13.4).
      **Kein Reboot nötig.**
- [x] **Phase 2 — Container-Toolkit.** `nvidia-container-toolkit` 1.20.1 installiert.
      **Achtung:** `/etc/apt/sources.list.d/nvidia-container-toolkit.list` war 0 Bytes — der
      von `install.sh` genutzte distributions-spezifische Repo-URL (`.../$distribution/...`) ist
      von NVIDIA deprecated (404 → leere Datei). Stattdessen kanonischen Repo genutzt:
      `deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/amd64 /`.
      Dann `sudo nvidia-ctk runtime configure --runtime=docker` + `systemctl restart docker`.
      Docker zeigt nun Runtime `nvidia`. Verifiziert mit
      `docker run --rm --gpus all --entrypoint nvidia-smi ollama/ollama:latest`.
- [x] **Phase 3 — Stacks konsolidieren.** `ollama-opt-docker` gestoppt (`docker compose down`),
      Daten per `sudo /usr/bin/mv` nach `/home/julian/{ollama,open-webui}` verschoben (gleiches
      Dateisystem → instant rename), die 3 Nebenstacks (`ollama/`, `ollama-opt-docker/`,
      `open-webui/`) im Working-Tree entfernt. **Git-Commit in `~/docker-stacks-home` steht noch
      aus** (Julian committet selbst). Zielstack hochgezogen, GPU-Offload verifiziert.

## Werkzeuge / Konventionen

- **sudo/interaktive Befehle:** über die tmux-Pane-Bridge laufen lassen —
  `~/BashScripts/scripts/claude-run-in-pane.sh "<cmd>"` (Alias `crun`), mit Bash-Tool-Flag
  `run_in_background: true`. Passwort tippt Julian im Ziel-Pane. Siehe Haupt-CLAUDE.md
  (`~/BashScripts/CLAUDE.md` → „sudo / interaktive Befehle: tmux-Pane-Bridge").
- `apt-get` ist auf `nala` gealiased → im Skript `/usr/bin/apt-get`.
- `tmux` ist in zsh gewrappt → `command tmux` / `/usr/bin/tmux`.
- **`mv` ist in Julians zsh ein Alias** (`echo 'Tipp: mvg…' && mv`). Dadurch wird `sudo mv x y`
  zu `sudo echo … && mv x y` → das echte `mv` läuft OHNE sudo (Permission denied). Für
  root-Datei操作 immer **`sudo /usr/bin/mv`** / `sudo /usr/bin/rm` mit vollem Pfad verwenden.
- **Pane-Bridge-Vorsicht:** Claudes Bash-Tool lief in dieser Session NICHT in tmux
  (`$TMUX` leer) → `claude-run-in-pane.sh` bricht ab (`Nicht in einer tmux-Session`). Julians
  Claude-TUI läuft aber in tmux-Session `0`. Workaround war ein Einmal-Skript, das per
  `command tmux split-window -t 0` ein Shell-Pane in Session 0 erzeugt und dort send-keys +
  Logfile/Sentinel nutzt (gleiche Logik wie die Bridge, nur ohne `$TMUX`-Pflicht).

## Referenzen
- Plan: `~/.claude/plans/kannst-du-s-generell-anbieten-imperative-quasar.md`
- Session-Log: `~/BashScripts/done/2026-10-30.md`
- GPU-README (A3000-spezifisch, Modelle/TTS): `~/docker-stacks-home/ollama-docker-w-gpu/README.md`
