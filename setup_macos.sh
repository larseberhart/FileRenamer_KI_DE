#!/usr/bin/env bash
# ==============================================================================
#  setup.sh — Einrichtungsskript für FileRenamerKIDE
# ==============================================================================
#
#  Dieses Skript prüft alle Voraussetzungen für FileRenamerKIDE und richtet
#  die Entwicklungsumgebung vollständig ein. Es führt folgende Schritte durch:
#
#    1. Prüft, ob Homebrew installiert ist (Pflicht für macOS-Pakete).
#    2. Prüft und installiert Python 3.10+ via Homebrew (falls nötig).
#    3. Prüft und installiert Tesseract OCR + Sprachpaket Deutsch + Poppler
#       (optional, aber empfohlen für gescannte PDFs).
#    4. Prüft und installiert Ollama (lokal laufendes KI-Modell).
#    5. Erstellt eine virtuelle Python-Umgebung (.venv) im Projektordner.
#    6. Installiert alle Python-Pakete aus requirements.txt in die venv.
#    7. Aktiviert die virtuelle Umgebung in der aktuellen Shell-Sitzung.
#    8. Startet Ollama im Hintergrund (falls noch nicht aktiv).
#
#  Vor jeder Installation wird explizit nach einer Bestätigung gefragt.
#  Bereits installierte Komponenten werden erkannt und übersprungen.
#
#  Aufruf:
#    chmod +x setup.sh   # einmalig ausführbar machen
#    ./setup.sh
#
#  Autor: Lars Eberhart
# ==============================================================================

# ------------------------------------------------------------------------------
# Sicherheitsoptionen:
#   -e  Skript bricht bei jedem Fehler sofort ab (kein stilles Scheitern).
#   -u  Nicht gesetzte Variablen werden als Fehler behandelt.
#   -o pipefail  Ein Fehler in einer Pipe-Kette gilt als Gesamtfehler.
# ------------------------------------------------------------------------------
set -euo pipefail

# ------------------------------------------------------------------------------
# Farbcodes für übersichtliche Terminal-Ausgabe.
# Werden nur gesetzt, wenn das Terminal Farben unterstützt (tput verfügbar).
# ------------------------------------------------------------------------------
if command -v tput &>/dev/null && tput colors &>/dev/null; then
    C_RESET=$(tput sgr0)
    C_BOLD=$(tput bold)
    C_GREEN=$(tput setaf 2)
    C_YELLOW=$(tput setaf 3)
    C_CYAN=$(tput setaf 6)
    C_RED=$(tput setaf 1)
else
    C_RESET="" C_BOLD="" C_GREEN="" C_YELLOW="" C_CYAN="" C_RED=""
fi

# ------------------------------------------------------------------------------
# Hilfsfunktionen für formatierte Ausgaben.
# ------------------------------------------------------------------------------

# Ausgabe eines Info-Hinweises (blaue/cyan Markierung).
info()    { echo "${C_CYAN}${C_BOLD}[info]${C_RESET}  $*"; }

# Ausgabe einer Erfolgsmeldung (grün).
ok()      { echo "${C_GREEN}${C_BOLD}[ok]${C_RESET}    $*"; }

# Ausgabe einer Warnung (gelb) — kein Abbruch.
warn()    { echo "${C_YELLOW}${C_BOLD}[warn]${C_RESET}  $*"; }

# Ausgabe eines Fehlers (rot) — danach Abbruch.
error()   { echo "${C_RED}${C_BOLD}[fehler]${C_RESET} $*" >&2; exit 1; }

# Trennlinie für bessere Lesbarkeit zwischen Abschnitten.
separator() { echo; echo "${C_BOLD}──────────────────────────────────────────────${C_RESET}"; echo; }

# ------------------------------------------------------------------------------
# ask_confirm <Frage>
#
# Stellt dem Benutzer eine Ja/Nein-Frage. Gibt 0 zurück bei Ja, 1 bei Nein.
# Akzeptiert: j / J / y / Y → Ja
#             n / N / Enter  → Nein (Standardantwort)
# ------------------------------------------------------------------------------
ask_confirm() {
    local prompt="$1"
    local answer
    # Prompt direkt ins Terminal schreiben (nicht über stdout, damit Pipes
    # den Text nicht verschlucken).
    printf "%s %s[j/N]%s " \
        "${C_YELLOW}${C_BOLD}[?]${C_RESET} ${prompt}" \
        "${C_BOLD}" "${C_RESET}" >/dev/tty
    read -r answer </dev/tty || answer="n"
    case "$answer" in
        [jJyY]) return 0 ;;
        *)       return 1 ;;
    esac
}

# ==============================================================================
# HEADER — Begrüßung und Übersicht
# ==============================================================================
clear
echo "${C_BOLD}${C_CYAN}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║          FileRenamerKIDE — Setup-Skript              ║"
echo "╚══════════════════════════════════════════════════════╝"
echo "${C_RESET}"
echo "Dieses Skript richtet alle Voraussetzungen für FileRenamerKIDE ein."
echo "Vor jeder Installation wird nach Bestätigung gefragt."
echo

# ==============================================================================
# SCHRITT 1: Homebrew prüfen (Pflichtvoraussetzung)
# ==============================================================================
separator
info "Schritt 1/6 — Homebrew prüfen"
echo "Homebrew wird benötigt, um Python, Tesseract und Ollama zu installieren."
echo

if command -v brew &>/dev/null; then
    ok "Homebrew ist bereits installiert: $(brew --version | head -1)"
else
    # Homebrew fehlt — ohne Homebrew können wir auf macOS keine Systempakete
    # installieren. Der Benutzer muss es manuell installieren.
    warn "Homebrew ist nicht installiert."
    echo "Homebrew ist auf macOS die Standardmethode zur Paketverwaltung."
    echo "Installationsbefehl (von https://brew.sh):"
    echo
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    echo
    if ask_confirm "Homebrew jetzt installieren?"; then
        info "Starte Homebrew-Installation ..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        ok "Homebrew wurde erfolgreich installiert."
    else
        error "Homebrew ist Pflichtvoraussetzung. Setup abgebrochen."
    fi
fi

# ==============================================================================
# SCHRITT 2: Python 3.10+ prüfen und ggf. installieren
# ==============================================================================
separator
info "Schritt 2/8 — Python 3.10+ prüfen"
echo "FileRenamerKIDE benötigt Python 3.10 oder neuer."
echo

# Sucht nach einem Python-Binary (python3 oder python), das mindestens
# Version 3.10 meldet.
PYTHON_BIN=""
for candidate in python3 python; do
    if command -v "$candidate" &>/dev/null; then
        # Versionsnummer als Integer auslesen: z. B. "3.11" → 311
        py_ver=$("$candidate" -c \
            "import sys; print(sys.version_info.major * 100 + sys.version_info.minor)" \
            2>/dev/null || echo "0")
        if [ "$py_ver" -ge 310 ]; then
            PYTHON_BIN="$candidate"
            break
        fi
    fi
done

if [ -n "$PYTHON_BIN" ]; then
    py_version=$("$PYTHON_BIN" --version 2>&1)
    ok "Python gefunden: $py_version (${PYTHON_BIN})"
else
    warn "Python 3.10+ nicht gefunden."
    echo "Homebrew kann Python 3 installieren:"
    echo "  brew install python3"
    echo
    if ask_confirm "Python 3 via Homebrew installieren?"; then
        info "Installiere Python 3 via Homebrew ..."
        brew install python3
        # Nach der Installation das neue Binary verwenden.
        PYTHON_BIN="python3"
        ok "Python 3 wurde erfolgreich installiert: $($PYTHON_BIN --version)"
    else
        error "Python 3.10+ ist erforderlich. Setup abgebrochen."
    fi
fi

# ==============================================================================
# SCHRITT 3: Tesseract OCR + Deutsch + Poppler (optional)
# ==============================================================================
separator
info "Schritt 3/8 — Tesseract OCR + Deutsch-Sprachpaket + Poppler prüfen (optional)"
echo "Diese Systemtools werden nur für gescannte PDFs ohne eingebetteten Text benötigt."
echo "Ohne Tesseract werden solche Dateien automatisch übersprungen."
echo
echo "  • tesseract      — OCR-Engine"
echo "  • tesseract-lang — Sprachpakete (inkl. Deutsch 'deu')"
echo "  • poppler        — PDF-zu-Bild-Konvertierung für pdf2image"
echo

# Jede Komponente wird einzeln geprüft, damit nur fehlende installiert werden.
MISSING_OCR_TOOLS=()

if ! command -v tesseract &>/dev/null; then
    MISSING_OCR_TOOLS+=("tesseract")
else
    ok "tesseract ist installiert: $(tesseract --version 2>&1 | head -1)"
    # Deutsch-Sprachpaket prüfen (tesseract --list-langs gibt Zeilen aus).
    if ! tesseract --list-langs 2>/dev/null | grep -q "^deu$"; then
        warn "Tesseract-Sprachpaket 'deu' (Deutsch) fehlt."
        MISSING_OCR_TOOLS+=("tesseract-lang")
    else
        ok "Tesseract-Sprachpaket 'deu' ist vorhanden."
    fi
fi

if ! command -v pdftoppm &>/dev/null; then
    # pdftoppm ist Teil von Poppler; sein Vorhandensein genügt als Prüfung.
    MISSING_OCR_TOOLS+=("poppler")
else
    ok "poppler ist installiert."
fi

if [ ${#MISSING_OCR_TOOLS[@]} -eq 0 ]; then
    ok "Alle OCR-Systemtools sind bereits installiert."
else
    warn "Folgende OCR-Systemtools fehlen: ${MISSING_OCR_TOOLS[*]}"
    echo
    if ask_confirm "Fehlende OCR-Systemtools via Homebrew installieren (empfohlen)?"; then
        info "Installiere: ${MISSING_OCR_TOOLS[*]} ..."
        brew install "${MISSING_OCR_TOOLS[@]}"
        ok "OCR-Systemtools wurden erfolgreich installiert."
    else
        warn "OCR-Systemtools werden übersprungen. Gescannte PDFs können nicht verarbeitet werden."
    fi
fi

# ==============================================================================
# SCHRITT 4: Ollama prüfen und ggf. installieren
# ==============================================================================
separator
info "Schritt 4/8 — Ollama prüfen"
echo "Ollama wird benötigt, um das lokale KI-Modell auszuführen."
echo "Standardmodell: qwen3.5:latest"
echo

if command -v ollama &>/dev/null; then
    ok "Ollama ist bereits installiert: $(ollama --version 2>/dev/null || echo 'Version unbekannt')"
else
    warn "Ollama ist nicht installiert."
    echo "Ollama kann via Homebrew installiert werden:"
    echo "  brew install ollama"
    echo
    if ask_confirm "Ollama via Homebrew installieren?"; then
        info "Installiere Ollama ..."
        brew install ollama
        ok "Ollama wurde erfolgreich installiert."
    else
        warn "Ollama wird übersprungen. Das Skript kann ohne Ollama nicht ausgeführt werden."
    fi
fi

# Zusatzhinweis: Modell herunterladen, falls Ollama gerade installiert wurde
# oder das Standardmodell noch nicht vorhanden ist.
if command -v ollama &>/dev/null; then
    echo
    info "Prüfe, ob das Standardmodell 'qwen3.5:latest' bereits heruntergeladen ist ..."
    # 'ollama list' gibt alle lokalen Modelle aus; grep sucht nach dem Modellnamen.
    if ollama list 2>/dev/null | grep -q "qwen3.5"; then
        ok "Modell 'qwen3.5:latest' ist bereits vorhanden."
    else
        warn "Modell 'qwen3.5:latest' wurde noch nicht heruntergeladen."
        echo "Das Herunterladen kann einige Minuten dauern (Größe: ~2-5 GB)."
        echo
        if ask_confirm "Modell 'qwen3.5:latest' jetzt herunterladen?"; then
            info "Lade Modell herunter (ollama pull qwen3.5:latest) ..."
            ollama pull qwen3.5:latest
            ok "Modell 'qwen3.5:latest' wurde erfolgreich heruntergeladen."
        else
            warn "Modell nicht heruntergeladen. Vor dem ersten Einsatz 'ollama pull qwen3.5:latest' ausführen."
        fi
    fi
fi

# ==============================================================================
# SCHRITT 5: Virtuelle Python-Umgebung erstellen
# ==============================================================================
separator
info "Schritt 5/8 — Virtuelle Python-Umgebung einrichten (.venv)"
echo "Eine virtuelle Umgebung isoliert die Python-Pakete dieses Projekts"
echo "vom System-Python und verhindert Konflikte mit anderen Projekten."
echo

VENV_DIR="$(pwd)/.venv"

if [ -d "$VENV_DIR" ]; then
    # Bereits vorhanden — prüfen ob sie funktionsfähig ist.
    ok ".venv-Verzeichnis existiert bereits: $VENV_DIR"
    if ask_confirm ".venv neu erstellen (löscht vorhandene Pakete)?"; then
        info "Entferne vorhandene .venv ..."
        # Aktive venv deaktivieren, damit keine Dateien durch den laufenden
        # Interpreter gesperrt sind. Die Funktion 'deactivate' existiert nur,
        # wenn eine venv aktiviert ist — daher der 'command -v'-Check.
        if command -v deactivate &>/dev/null; then
            deactivate 2>/dev/null || true
        fi
        # rm -rf schlägt auf macOS gelegentlich bei erweiterten Attributen
        # oder gesperrten Dateien fehl. Python's shutil.rmtree ist robuster
        # und umgeht diese Einschränkungen zuverlässig.
        if ! rm -rf "$VENV_DIR" 2>/dev/null; then
            warn "rm -rf fehlgeschlagen — verwende shutil.rmtree als Fallback ..."
            "$PYTHON_BIN" -c "import shutil; shutil.rmtree('${VENV_DIR}')"
        fi
        info "Erstelle neue virtuelle Umgebung ..."
        "$PYTHON_BIN" -m venv "$VENV_DIR"
        ok "Virtuelle Umgebung neu erstellt."
    else
        info "Vorhandene .venv wird weiterverwendet."
    fi
else
    info "Erstelle virtuelle Umgebung in $VENV_DIR ..."
    "$PYTHON_BIN" -m venv "$VENV_DIR"
    ok "Virtuelle Umgebung erfolgreich erstellt."
fi

# Aktivierungspfad des venv-Python-Interpreters (nicht source, da wir im
# selben Subshell-Kontext bleiben müssen).
VENV_PYTHON="$VENV_DIR/bin/python"
VENV_PIP="$VENV_DIR/bin/pip"

# ==============================================================================
# SCHRITT 6: Python-Pakete aus requirements.txt installieren
# ==============================================================================
separator
info "Schritt 6/8 — Python-Pakete installieren (requirements.txt)"
echo "Folgende Pakete werden in die virtuelle Umgebung installiert:"
echo
# Kommentare und Leerzeilen aus requirements.txt filtern und anzeigen.
grep -v '^\s*#' requirements.txt | grep -v '^\s*$' | sed 's/^/  • /'
echo

if ask_confirm "Pakete jetzt in .venv installieren?"; then
    info "Aktualisiere pip auf die neueste Version ..."
    "$VENV_PYTHON" -m pip install --upgrade pip

    info "Installiere Pakete aus requirements.txt ..."
    "$VENV_PIP" install -r requirements.txt
    ok "Alle Python-Pakete wurden erfolgreich installiert."
else
    warn "Paketinstallation übersprungen. Skript wird ohne Python-Pakete nicht funktionieren."
    warn "Manuell nachholen mit: source .venv/bin/activate && pip install -r requirements.txt"
fi

# ==============================================================================
# SCHRITT 7: Virtuelle Umgebung in der aktuellen Shell aktivieren
# ==============================================================================
separator
info "Schritt 7/8 — Virtuelle Umgebung aktivieren"
echo "Die venv wird in der aktuellen Shell-Sitzung aktiviert."
echo "Hinweis: Wird das Skript als './setup.sh' gestartet (Subshell), ist die"
echo "Aktivierung nur innerhalb dieses Skripts gültig. Für die eigene Shell"
echo "danach noch einmal 'source .venv/bin/activate' ausführen."
echo

if ask_confirm "Virtuelle Umgebung jetzt aktivieren (source .venv/bin/activate)?"; then
    # shellcheck source=/dev/null
    # Aktivierung per 'source' (Punkt-Operator), damit Umgebungsvariablen
    # (PATH, VIRTUAL_ENV usw.) in die aktuelle Shell übernommen werden.
    # In einer Subshell (./setup.sh) wirkt dies nur für die Laufzeit des Skripts;
    # in einer gesourcten Sitzung (source ./setup.sh) bleibt sie dauerhaft aktiv.
    source "$VENV_DIR/bin/activate"
    ok "Virtuelle Umgebung aktiviert: $VIRTUAL_ENV"
else
    warn "Aktivierung übersprungen. Vor dem Ausführen des Skripts manuell aktivieren:"
    warn "  source .venv/bin/activate"
fi

# ==============================================================================
# SCHRITT 8: Ollama im Hintergrund starten
# ==============================================================================
separator
info "Schritt 8/8 — Ollama starten"
echo "Ollama muss als Hintergrunddienst laufen, damit das Sprachmodell"
echo "Anfragen entgegennehmen kann."
echo

# Prüfen ob Ollama bereits aktiv ist: 'ollama list' schlägt fehl, wenn der
# Dienst nicht läuft. Alternativ: Port 11434 auf offene Verbindungen prüfen.
OLLAMA_RUNNING=false
if command -v ollama &>/dev/null; then
    if ollama list &>/dev/null 2>&1; then
        OLLAMA_RUNNING=true
    fi
fi

if $OLLAMA_RUNNING; then
    ok "Ollama läuft bereits."
else
    if ! command -v ollama &>/dev/null; then
        warn "Ollama ist nicht installiert — Schritt übersprungen."
    else
        warn "Ollama ist nicht aktiv."
        echo
        if ask_confirm "Ollama jetzt im Hintergrund starten (ollama serve)?"; then
            info "Starte Ollama im Hintergrund ..."
            # 'nohup ... &' startet Ollama entkoppelt von dieser Shell,
            # sodass es nach Ende des Skripts weiterläuft.
            # Stdout/Stderr werden in ~/.ollama/setup-serve.log umgeleitet,
            # um das Terminal nicht zu blockieren.
            nohup ollama serve >> ~/.ollama/setup-serve.log 2>&1 &
            OLLAMA_PID=$!
            info "Warte kurz auf Ollama-Start (PID $OLLAMA_PID) ..."
            # Bis zu 10 Sekunden warten, bis der API-Port antwortet.
            for i in $(seq 1 10); do
                if ollama list &>/dev/null 2>&1; then
                    ok "Ollama ist gestartet und bereit (PID $OLLAMA_PID)."
                    break
                fi
                sleep 1
                if [ "$i" -eq 10 ]; then
                    warn "Ollama antwortet noch nicht — läuft aber im Hintergrund weiter."
                    warn "Log: ~/.ollama/setup-serve.log"
                fi
            done
        else
            warn "Ollama wird nicht gestartet. Vor dem ersten Einsatz manuell starten:"
            warn "  ollama serve"
        fi
    fi
fi

# ==============================================================================
# ABSCHLUSS — Zusammenfassung und nächste Schritte
# ==============================================================================
separator
echo "${C_GREEN}${C_BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║           Setup abgeschlossen!                       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo "${C_RESET}"
echo "Nächste Schritte:"
echo

# Prüfen ob die venv bereits aktiv ist ($VIRTUAL_ENV wird von 'source activate'
# gesetzt). Ist sie es nicht, wird die Aktivierung jetzt noch einmal angeboten —
# z. B. wenn Schritt 7 übersprungen wurde oder das Skript neu gestartet wurde.
if [ -z "${VIRTUAL_ENV:-}" ]; then
    if ask_confirm "Virtuelle Umgebung jetzt in dieser Shell aktivieren (source .venv/bin/activate)?"; then
        # shellcheck source=/dev/null
        source "$VENV_DIR/bin/activate"
        ok "Virtuelle Umgebung aktiviert: $VIRTUAL_ENV"
    else
        echo
        echo "  Virtuelle Umgebung manuell aktivieren:"
        echo "     ${C_BOLD}source .venv/bin/activate${C_RESET}"
    fi
else
    ok "Virtuelle Umgebung ist bereits aktiv: $VIRTUAL_ENV"
fi
echo
echo "  Skript ausführen (Vorschau ohne Umbenennung):"
echo "     ${C_BOLD}python filerenamerkide.py ~/Dokumente/Rechnungen --dry-run${C_RESET}"
echo
echo "  Tatsächliche Umbenennung durchführen:"
echo "     ${C_BOLD}python filerenamerkide.py ~/Dokumente/Rechnungen${C_RESET}"
echo
