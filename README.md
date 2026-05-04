# FileRenamer

Intelligente PDF-Umbenennung mit einem lokal laufenden KI-Modell (Ollama).

Das Skript liest den eingebetteten Text aus PDF-Dateien, sendet ihn an ein
lokales Ollama-Sprachmodell und benennt die Datei anschließend nach einem
einheitlichen, gut lesbaren Schema um:

```
YYYY-MM-DD_Dokumenttyp_Absender Stichwort2 Stichwort3.pdf
```

**Beispiele:**
```
2024-03-15_Rechnung_Amazon Bestellung-12345.pdf
2023-11-01_Vertrag_Wiener Wohnen Mietvertrag Wien.pdf
2022-06-30_Kontoauszug_Trottelbank Girokonto März.pdf
2017-04-26_Rechnung_T-Mobile Rechnung SIM.pdf
```

---

## Voraussetzungen

- **Python 3.10** oder neuer
- **Ollama** lokal installiert und gestartet (`ollama serve`)
- Ein heruntergeladenes Ollama-Modell (getestet mit `qwen3.5:latest` und `llama3.2:latest`)
- Textbasierte PDFs werden direkt unterstützt. Für **gescannte PDFs ohne eingebetteten Text** greift das Skript automatisch auf Tesseract OCR zurück (optionale Installation, siehe unten)

---

## Installation

> **Tipp:** Wer die Einrichtung nicht manuell durchführen möchte, kann stattdessen das mitgelieferte Setup-Skript verwenden, es übernimmt alle nachfolgenden Schritte automatisch. 

---

## Automatische Einrichtung mit `setup.sh`

Anstatt alle Voraussetzungen einzeln von Hand zu installieren, kann das
mitgelieferte Skript `setup.sh` die gesamte Einrichtung übernehmen.
Es prüft jeden Schritt, fragt vor jeder Installation nach einer Bestätigung
und gibt dabei fortlaufend aus, was es tut.

### Was das Skript einrichtet

Das Skript führt, mit Bestätigung vor jedem Schritt, folgende Aktionen aus:

| Schritt | Aktion |
|---|---|
| 1 | **Homebrew** prüfen und bei Bedarf installieren (Pflicht für alle weiteren Schritte) |
| 2 | **Python 3.10+** prüfen und bei Bedarf via Homebrew installieren |
| 3 | **Tesseract OCR**, Deutsch-Sprachpaket (`deu`) und **Poppler** prüfen und bei Bedarf installieren (optional, für gescannte PDFs) |
| 4 | **Ollama** prüfen, bei Bedarf installieren und das Standardmodell `qwen3.5:latest` herunterladen |
| 5 | Virtuelle Python-Umgebung **`.venv`** erstellen (oder auf Wunsch neu anlegen) |
| 6 | Alle **Python-Pakete** aus `requirements.txt` in die venv installieren |
| 7 | Die virtuelle Umgebung in der aktuellen Shell-Sitzung **aktivieren** |
| 8 | **Ollama** im Hintergrund starten (`ollama serve`), falls noch nicht aktiv |

Bereits installierte Komponenten werden automatisch erkannt und übersprungen, es wird also nichts doppelt installiert.

### Voraussetzungen

- macOS (das Skript setzt Homebrew als Paketmanager voraus)
- Eine aktive Internetverbindung (für die Installation fehlender Pakete)

### Verwendung

```bash
# Einmalig: Skript ausführbar machen
chmod +x setup.sh

# Skript starten
./setup.sh
```

Das Skript führt durch alle Schritte und fragt bei jeder Installation nach
einer Bestätigung (`j` für Ja, `n` / Enter für Nein). Wer einen Schritt
überspringen möchte, antwortet einfach mit `n` alle übrigen Schritte
werden trotzdem angeboten.

### Hinweis zur venv-Aktivierung

Wird das Skript als `./setup.sh` gestartet, läuft es in einer Subshell.
Die venv-Aktivierung in Schritt 7 gilt dann nur für die Laufzeit des Skripts
selbst. Um die venv dauerhaft in der eigenen Shell-Sitzung zu aktivieren,
einmalig nach dem Setup ausführen:

```bash
source .venv/bin/activate
```

---

## Manuelle Installation

### 1. Repository klonen oder Dateien herunterladen

```bash
git clone <repository-url>
cd FileRenamer
```

### 2. Virtuelle Python-Umgebung erstellen und aktivieren

Eine virtuelle Umgebung isoliert die installierten Pakete vom System-Python
und verhindert Konflikte mit anderen Projekten.

```bash
# Virtuelle Umgebung erstellen (einmalig)
python3 -m venv .venv

# Aktivieren (macOS / Linux)
source .venv/bin/activate

```

### 3. Abhängigkeiten installieren

```bash
pip install -r requirements.txt
```

Dies installiert alle Pakete inklusive der optionalen OCR-Abhängigkeiten
`pytesseract`, `pdf2image` und `Pillow`.

### 4. Tesseract installieren (für gescannte PDFs, empfohlen)

Für PDFs ohne eingebetteten Text (gescannte Dokumente) wird Tesseract OCR
als automatischer Fallback verwendet. Dafür sind zwei Systemtools notwendig:

```bash
# macOS (via Homebrew)
brew install tesseract tesseract-lang poppler
```

| Tool | Zweck |
|---|---|
| `tesseract` | OCR-Engine |
| `tesseract-lang` | Sprachpakete, inkl. Deutsch (`deu`) |
| `poppler` | PDF-zu-Bild-Konvertierung für `pdf2image` |

Ist Tesseract nicht installiert, werden gescannte PDFs automatisch übersprungen
und ein entsprechender Hinweis ausgegeben der Rest funktioniert weiterhin normal.

### 5. Ollama-Modell herunterladen

```bash
# Empfohlenes Modell (Standard):
ollama pull qwen3.5:latest

# Alternatives, kleineres Modell:
ollama pull llama3.2:latest
```

### 6. Ollama starten (falls noch nicht aktiv)

```bash
ollama serve
```

Ollama läuft standardmäßig unter `http://127.0.0.1:11434`. Das Skript
verwendet diesen Endpunkt automatisch.

---

## Verwendung

### Virtuelle Umgebung aktivieren (bei jedem neuen Terminal)

```bash
source .venv/bin/activate
```

### Vorschau ohne Umbenennung (empfohlen zum Testen)

```bash
python filerenamerkide.py ~/Dokumente/Rechnungen --dry-run
```

Mit `--dry-run` werden die vorgeschlagenen Dateinamen nur angezeigt,
ohne dass tatsächlich Dateien umbenannt werden.

### Umbenennung durchführen

```bash
python filerenamerkide.py ~/Dokumente/Rechnungen
```

### Unterordner rekursiv verarbeiten

```bash
python filerenamerkide.py ~/Dokumente --recursive
```

### Einzelne Datei umbenennen

```bash
python filerenamerkide.py ~/Desktop/rechnung.pdf
```

### Anderes Modell verwenden

```bash
python filerenamerkide.py ~/Dokumente/Rechnungen --model llama3.2:latest
```

### Ausführliche Diagnoseausgabe

```bash
python filerenamerkide.py ~/Dokumente/Rechnungen --verbose
```

Mit `--verbose` wird zusätzlich der rohe Ollama-Response und eine Textvorschau
der PDF-Extraktion ausgegeben nützlich bei der Fehlersuche.

---

## Alle Optionen im Überblick

| Option | Standard | Beschreibung |
|---|---|---|
| `path` | `.` (aktuelles Verzeichnis) | PDF-Datei oder Verzeichnis, das verarbeitet werden soll |
| `--model` | `qwen3.5:latest` | Name des Ollama-Modells |
| `--ollama-url` | `http://127.0.0.1:11434/api/generate` | URL des Ollama-Endpunkts |
| `--recursive` | aus | Unterordner rekursiv durchsuchen |
| `--dry-run` | aus | Nur Vorschau, keine Umbenennung |
| `--max-pages` | `5` | Maximale Anzahl Seiten, die pro PDF gelesen werden |
| `--max-chars` | `6000` | Maximale Zeichenanzahl, die ans Modell gesendet wird |
| `--verbose` | aus | Zusätzliche Diagnoseausgaben anzeigen |

---

## Ausgabe-Schema

Das Skript gibt für jede Datei eine detaillierte Statuszeile aus:

```
[info] 3 PDF(s) gefunden in /Users/.../Rechnungen
[info] Modell: qwen3.5:latest
[info] Ollama-URL: http://127.0.0.1:11434/api/generate
[info] Dry-run: False

[1/3] rechnung_april.pdf

--- Verarbeite: rechnung_april.pdf ---
  [extract] Öffne PDF: rechnung_april.pdf
  [extract] Seiten gesamt: 2 (lese bis zu 5)
  [extract] Seite 1: 1842 Zeichen
  [extract] Seite 2: 634 Zeichen
  [extract] Extrahiert gesamt: 2476 Zeichen
  [ollama] Sende Anfrage an http://127.0.0.1:11434/api/generate mit Modell 'qwen3.5:latest'
  [ollama] Warte auf Antwort...
  [ollama] Antwort erhalten (512 Bytes)
  [ollama] Geparstes JSON: {'date': '2024-04-01', 'doc_type': 'Rechnung', 'keywords': 'Amazon, Bestellung-12345, Kindle'}
  [ollama] date='2024-04-01', doc_type='Rechnung', keywords='Amazon Bestellung-12345 Kindle'
  [ollama] Vorgeschlagener Dateiname: '2024-04-01_Rechnung_Amazon Bestellung-12345 Kindle'
  [rename] rechnung_april.pdf -> 2024-04-01_Rechnung_Amazon Bestellung-12345 Kindle.pdf
OK    rechnung_april.pdf -> 2024-04-01_Rechnung_Amazon Bestellung-12345 Kindle.pdf (umbenannt)
```

**Statuszeilen am Ende:**
- `OK` Datei erfolgreich umbenannt
- `ÜBERSPRUNGEN` Datei übersprungen (kein extrahierbarer Text)
- `FEHLER` Fehler bei der Verarbeitung (z. B. Ollama nicht erreichbar)

**Exit Codes:**
- `0`: Alle Dateien erfolgreich verarbeitet
- `1`: Schwerwiegender Fehler (Ollama nicht erreichbar, Pfad nicht gefunden)
- `2`: Mindestens eine Datei wurde übersprungen

---

## Funktionsweise im Detail

1. **PDF-Erkennung** Das Skript findet alle `.pdf`-Dateien im angegebenen Pfad (optional rekursiv).
2. **Textextraktion** Mit `pypdf` wird der eingebettete Text seitenweise extrahiert und auf `--max-chars` Zeichen begrenzt.
3. **OCR-Fallback** Enthält die PDF keinen eingebetteten Text (z. B. gescannte Dokumente), werden die Seiten automatisch mit `pdf2image` in Bilder umgewandelt und per Tesseract OCR (Sprache: Deutsch) ausgelesen. Ist das deutsche Sprachpaket nicht installiert, wird auf Englisch zurückgefallen. Fehlen `pytesseract` oder `pdf2image` komplett, wird die Datei übersprungen.
4. **KI-Analyse** Der Text wird zusammen mit einem deutschen Prompt an Ollama gesendet. Das Modell gibt ein JSON-Objekt zurück mit:
   - `date` Dokumentdatum im Format `YYYY-MM-DD`
   - `doc_type` Dokumenttyp auf Deutsch (Rechnung, Vertrag, Kontoauszug, …)
   - `keywords` 2–4 Stichworte in festgelegter Reihenfolge: Absender, Kennung, Thema, Detail
5. **Bereinigung** Sonderzeichen werden entfernt, Leerzeichen innerhalb eines Stichworts bleiben erhalten. Deutsche Umlaute (ä, ö, ü, Ä, Ö, Ü, ß) bleiben erhalten.
6. **Kollisionsvermeidung** Existiert der Zieldateiname bereits, wird automatisch `-2`, `-3` usw. angehängt.
7. **Umbenennung** Die Datei wird direkt im selben Ordner umbenannt.

---

## Hinweise und Einschränkungen

- **Gescannte PDFs** Diese werden automatisch per Tesseract OCR verarbeitet, sofern `pytesseract`, `pdf2image` und das Tesseract-Systemtool installiert sind. Fehlen diese, wird die Datei übersprungen.
- **OCR-Qualität** Die Erkennungsgenauigkeit von Tesseract hängt von der Scan-Qualität ab. Bei sehr schlechten Scans (niedrige Auflösung, Handschrift) kann die Benennung ungenau ausfallen.
- **Qualität der Benennung** Hängt direkt vom verwendeten Modell und der Qualität des extrahierten Textes ab. Größere Modelle liefern in der Regel bessere Ergebnisse.
- **Reasoning-Modelle** (z. B. `qwen3.5`), die ihre Antwort im `thinking`-Feld statt im `response`-Feld zurückgeben, werden automatisch erkannt und unterstützt.
- **Keine Netzwerkverbindung erforderlich** Das gesamte Modell und OCR laufen lokal auf dem eigenen Rechner.

---

## Abhängigkeiten

| Paket | Version | Zweck |
|---|---|---|
| `pypdf` | ≥ 4.2, < 6.0 | Textextraktion aus textbasierten PDF-Dateien |
| `pytesseract` | ≥ 0.3.10 | Python-Wrapper für Tesseract OCR (OCR-Fallback) |
| `pdf2image` | ≥ 1.17.0 | Konvertierung von PDF-Seiten zu Bildern für OCR |
| `Pillow` | ≥ 10.0.0 | Bildverarbeitung (Abhängigkeit von pdf2image) |

Zusätzlich werden für den OCR-Fallback folgende **Systemtools** benötigt (nicht per pip installierbar):

| Tool | Installation (macOS) | Zweck |
|---|---|---|
| `tesseract` | `brew install tesseract` | OCR-Engine |
| Sprachpaket `deu` | `brew install tesseract-lang` | Deutsches Tesseract-Modell |
| `poppler` | `brew install poppler` | PDF-Rendering für pdf2image |

Alle weiteren verwendeten Module (`argparse`, `json`, `re`, `urllib`, …) sind Teil der Python-Standardbibliothek.

---

*Autor: Lars Eberhart*
