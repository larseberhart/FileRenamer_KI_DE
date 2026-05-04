#!/usr/bin/env python3
"""
filerenamerkide.py — Intelligente PDF-Umbenennung mit lokalem KI-Modell (Ollama)
=============================================================================

Dieses Skript liest den Text aus PDF-Dateien, sendet ihn an ein lokal
laufendes Ollama-Sprachmodell und lässt es einen aussagekräftigen Dateinamen
vorschlagen. Das Ergebnis folgt immer dem Schema:

    YYYY-MM-DD_Dokumenttyp_Stichwort1 Stichwort2.pdf

Beispiele:
    2024-03-15_Rechnung_Amazon Bestellnr-12345 Artikel.pdf
    2023-11-01_Vertrag_Vermieter GmbH Mietvertrag Berlin.pdf
    2022-06-30_Kontoauszug_Musterbank Girokonto.pdf

Funktionsweise
--------------
1.  Alle PDF-Dateien im angegebenen Pfad (oder eine einzelne Datei) werden
    gefunden und alphabetisch (ohne Berücksichtigung der Groß-/Kleinschreibung)
    verarbeitet.
2.  Aus jeder PDF werden bis zu ``--max-pages`` Seiten gelesen und der Text
    auf ``--max-chars`` Zeichen gekürzt, bevor er ans Modell gesendet wird.
    Das schützt vor zu langen Prompts und hält die Antwortzeiten gering.
3.  Das Ollama-Modell erhält einen deutschen Prompt und gibt ein JSON-Objekt
    mit den Feldern ``date``, ``doc_type`` und ``keywords`` zurück.
4.  Die zurückgegebenen Werte werden bereinigt (Umlaute transliteriert,
    Sonderzeichen entfernt) und zu einem sicheren Dateinamen zusammengesetzt.
5.  Bei Namenskollisionen wird automatisch ein Zähler angehängt (-2, -3, …).
6.  Im ``--dry-run``-Modus werden nur die vorgeschlagenen Namen ausgegeben,
    ohne tatsächlich Dateien umzubenennen.
7.  Dateien, die nicht geöffnet werden können (z. B. verschlüsselte PDFs),
    werden übersprungen; die übrigen Dateien werden weiterverarbeitet.

Unterstützte Modelle
--------------------
Getestet mit ``qwen3.5:latest`` (Standard) und ``llama3.2:latest``.
Reasoning-Modelle (die den JSON-Output in das ``thinking``-Feld schreiben
statt in ``response``) werden automatisch erkannt und unterstützt.

Voraussetzungen
---------------
- Python 3.10+
- pypdf >= 4.2 (``pip install pypdf``)
- Ollama läuft lokal unter http://127.0.0.1:11434
- Das gewünschte Modell wurde mit ``ollama pull <modell>`` heruntergeladen

Aufruf
------
    # Vorschau ohne Umbenennung:
    python filerenamerkide.py ~/Dokumente/Rechnungen --dry-run --recursive

    # Tatsächliche Umbenennung:
    python filerenamerkide.py ~/Dokumente/Rechnungen --recursive

    # Einzelne Datei mit anderem Modell:
    python filerenamerkide.py rechnung.pdf --model llama3.2:latest

OCR-Fallback
------------
Ist in einer PDF kein eingebetteter Text vorhanden (z. B. bei gescannten
Dokumenten), versucht das Skript automatisch, den Text per Tesseract OCR zu
extrahieren. Dafür werden die Pakete ``pytesseract`` und ``pdf2image`` sowie
die Systemtools ``tesseract`` (mit Sprachpaket ``deu``) und ``poppler``
benötigt:

    brew install tesseract tesseract-lang poppler
    pip install pytesseract pdf2image

Fehlen diese, wird die Datei übersprungen.

Einschränkungen
---------------
- Die Qualität des Dateinamens hängt direkt von der Qualität des OCR-Texts und
  der Leistungsfähigkeit des verwendeten Modells ab.
- Alle Ausgaben erfolgen auf Deutsch.

Autor: Lars Eberhart
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable
from urllib import error, request

from pypdf import PdfReader

# pytesseract und pdf2image sind optionale Abhängigkeiten für den OCR-Fallback.
# Sind sie nicht installiert, wird OCR still übersprungen.
try:
    import pytesseract
    from pdf2image import convert_from_path as _pdf2images

    _OCR_AVAILABLE = True
except ImportError:
    _OCR_AVAILABLE = False


DEFAULT_MODEL = "qwen3.5:latest"
DEFAULT_OLLAMA_URL = "http://127.0.0.1:11434/api/generate"
MAX_FILENAME_LENGTH = 120


def sanitize_date(value: str) -> str:
    """Gibt value zurück, wenn es dem Format YYYY-MM-DD entspricht, andernfalls '0000-00-00'."""
    value = value.strip()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        return value
    return "0000-00-00"


def sanitize_segment(value: str) -> str:
    """Behält Buchstaben (inkl. Umlaute), Ziffern und Bindestriche; fasst Leerzeichen zu Bindestrichen zusammen."""
    value = value.strip()
    value = re.sub(r"\s+", "-", value)
    value = re.sub(
        r"[^A-Za-z\u00c4\u00d6\u00dc\u00e4\u00f6\u00fc\u00df0-9-]", "", value
    )
    value = re.sub(r"-+", "-", value).strip("-")
    return value or "Dokument"


def sanitize_keywords(value: str) -> str:
    """Verarbeitet eine kommagetrennte Stichwortliste und verbindet die bereinigten Teile mit Leerzeichen."""
    parts = [p.strip() for p in value.split(",") if p.strip()]
    cleaned: list[str] = []
    for part in parts[:4]:
        part = re.sub(
            r"[^A-Za-z\u00c4\u00d6\u00dc\u00e4\u00f6\u00fc\u00df0-9 -]", "", part
        )
        part = re.sub(r" +", " ", part).strip()
        part = re.sub(r"-+", "-", part).strip("-")
        if part:
            cleaned.append(part)
    return " ".join(cleaned) or "unbekannt"


def build_filename(date: str, doc_type: str, keywords: str) -> str:
    name = f"{date}_{doc_type}_{keywords}"
    return name[:MAX_FILENAME_LENGTH].rstrip("_-") or "0000-00-00_Dokument_unbekannt"


@dataclass
class RenameResult:
    source: Path
    target: Path | None
    reason: str
    is_error: bool = False


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="PDF-Dateien anhand ihres Inhalts mit einem lokalen Ollama-Modell umbenennen."
    )
    parser.add_argument(
        "path",
        nargs="?",
        default=".",
        help="PDF-Datei oder Verzeichnis. Standard: aktuelles Verzeichnis.",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=f"Name des Ollama-Modells. Standard: {DEFAULT_MODEL}.",
    )
    parser.add_argument(
        "--ollama-url",
        default=DEFAULT_OLLAMA_URL,
        help=f"Ollama-Generate-Endpunkt. Standard: {DEFAULT_OLLAMA_URL}.",
    )
    parser.add_argument(
        "--recursive",
        action="store_true",
        help="Unterverzeichnisse rekursiv durchsuchen.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Vorgeschlagene Dateinamen anzeigen, ohne Dateien umzubenennen.",
    )
    parser.add_argument(
        "--max-pages",
        type=int,
        default=5,
        help="Maximale Seitenanzahl pro PDF. Standard: 5.",
    )
    parser.add_argument(
        "--max-chars",
        type=int,
        default=6000,
        help="Maximale Zeichenanzahl, die ans Modell gesendet wird. Standard: 6000.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Zusätzliche Diagnoseausgaben anzeigen.",
    )
    return parser.parse_args()


def discover_pdfs(path: Path, recursive: bool) -> list[Path]:
    if path.is_file():
        return [path] if path.suffix.lower() == ".pdf" else []
    pattern = "**/*.pdf" if recursive else "*.pdf"
    return sorted(
        (pdf for pdf in path.glob(pattern) if pdf.is_file()),
        key=lambda p: p.name.lower(),
    )


def _ocr_pdf(pdf_path: Path, max_pages: int, max_chars: int) -> str:
    """Konvertiert PDF-Seiten zu Bildern und extrahiert Text per Tesseract (Deutsch)."""
    if not _OCR_AVAILABLE:
        print("  [ocr] pytesseract/pdf2image nicht installiert — OCR übersprungen.")
        print("  [ocr] Installation: pip install pytesseract pdf2image")
        print("  [ocr] Systemtools:  brew install tesseract tesseract-lang poppler")
        return ""

    print(f"  [ocr] Starte Tesseract OCR (Sprache: deu, max. {max_pages} Seiten) ...")
    try:
        # PDF-Seiten als Bilder rendern (300 dpi für gute OCR-Qualität)
        images = _pdf2images(str(pdf_path), last_page=max_pages, dpi=300)
    except Exception as exc:
        print(f"  [ocr] Konvertierung fehlgeschlagen: {exc}")
        return ""

    # Verfügbare Tesseract-Sprachen prüfen; Fallback auf Englisch
    try:
        available_langs = pytesseract.get_languages()
        lang = "deu" if "deu" in available_langs else "eng"
        if lang != "deu":
            print(
                "  [ocr] Warnung: Tesseract-Sprachpaket 'deu' nicht gefunden, verwende 'eng'."
            )
            print("  [ocr] Installation: brew install tesseract-lang")
    except Exception:
        lang = "deu"

    snippets: list[str] = []
    total_chars = 0
    for i, image in enumerate(images, start=1):
        try:
            raw = pytesseract.image_to_string(image, lang=lang)
        except Exception as exc:
            print(f"  [ocr] Seite {i}: Tesseract-Fehler: {exc}")
            continue
        cleaned = " ".join(raw.split())
        print(f"  [ocr] Seite {i}: {len(cleaned)} Zeichen erkannt")
        if cleaned:
            snippets.append(cleaned)
            total_chars += len(cleaned)
        if total_chars >= max_chars:
            print(f"  [ocr] max_chars-Limit ({max_chars}) erreicht, Abbruch")
            break

    result = "\n".join(snippets)[:max_chars].strip()
    print(f"  [ocr] OCR-Extraktion abgeschlossen: {len(result)} Zeichen gesamt")
    return result


def extract_pdf_text(
    pdf_path: Path, max_pages: int, max_chars: int, verbose: bool = False
) -> str:
    print(f"  [extract] Öffne PDF: {pdf_path.name}")
    try:
        reader = PdfReader(str(pdf_path))
    except Exception as exc:
        print(f"  [extract] PDF kann nicht geöffnet werden: {exc}")
        return ""
    total_pages = len(reader.pages)
    print(f"  [extract] Seiten gesamt: {total_pages} (lese bis zu {max_pages})")
    snippets: list[str] = []
    total_chars = 0
    for i, page in enumerate(reader.pages[:max_pages], start=1):
        text = page.extract_text() or ""
        cleaned = " ".join(text.split())
        print(f"  [extract] Seite {i}: {len(cleaned)} Zeichen")
        if cleaned:
            snippets.append(cleaned)
            total_chars += len(cleaned)
        if total_chars >= max_chars:
            print(f"  [extract] max_chars-Limit ({max_chars}) erreicht, Abbruch")
            break
    joined = "\n".join(snippets)
    result = joined[:max_chars].strip()
    print(f"  [extract] Extrahiert gesamt: {len(result)} Zeichen")
    if verbose and result:
        print(f"  [extract] Textvorschau: {result[:300]!r}...")

    # Kein eingebetteter Text gefunden → OCR-Fallback mit Tesseract
    if not result:
        print("  [extract] Kein eingebetteter Text gefunden, versuche OCR-Fallback ...")
        result = _ocr_pdf(pdf_path, max_pages=max_pages, max_chars=max_chars)
        if verbose and result:
            print(f"  [ocr] Textvorschau: {result[:300]!r}...")

    return result


def build_prompt(file_name: str, extracted_text: str) -> str:
    return (
        "Du bist ein Assistent, der PDF-Dateien anhand ihres Inhalts umbenennt.\n"
        "Analysiere den folgenden PDF-Text und gib ausschliesslich ein gueltiges JSON-Objekt "
        "mit genau diesen drei Schlüsseln zurück:\n"
        '  "date": Das Datum des Dokuments (Rechnungsdatum, Vertragsdatum, Belegdatum usw.) '
        'im Format YYYY-MM-DD. Falls kein Datum gefunden wird, verwende "0000-00-00".\n'
        '  "doc_type": Der Dokumenttyp auf Deutsch, genau ein Wort '
        "(z. B. Rechnung, Vertrag, Abrechnung, Bestellung, Kontoauszug, Lieferschein, "
        "Mahnung, Quittung, Lohnabrechnung, Vertrag).\n"
        '  "keywords": Kommagetrennte Liste mit zwei bis vier Stichworten (im Dateinamen werden sie durch Leerzeichen getrennt). '
        "Die Reihenfolge ist zwingend einzuhalten: "
        "1. Absender des Dokuments (Firma, Behoerde oder Person, die das Dokument ausgestellt hat) — dieser Eintrag ist Pflicht. "
        "2. Auftragsnummer, Rechnungsnummer oder eine andere eindeutige Kennung, falls vorhanden. "
        "3. Produkt, Dienstleistung, Vertragsnummer oder Hauptthema des Dokuments. "
        "4. Ein weiteres inhaltliches Stichwort, das den Kontext praezisiert (z. B. Tarifname, Standort, Artikelbezeichnung). "
        "Den Empfaenger des Dokuments niemals als Stichwort aufnehmen. "
        "Das Wort 'Versandkosten' niemals als Stichwort verwenden. "
        "Leerzeichen innerhalb eines Stichworts beibehalten (nicht durch Bindestriche ersetzen), "
        "deutsche Umlaute (ä, ö, ü, ß, Ä, Ö, Ü) sind erlaubt, alle anderen Sonderzeichen weglassen.\n"
        "Keine weiteren Erklaerungen, nur das JSON-Objekt.\n\n"
        f"Dateiname: {file_name}\n"
        "Extrahierter PDF-Text:\n"
        f"{extracted_text}\n"
    )


def request_filename_from_ollama(
    *,
    pdf_path: Path,
    extracted_text: str,
    model: str,
    ollama_url: str,
    verbose: bool = False,
) -> str:
    print(f"  [ollama] Sende Anfrage an {ollama_url} mit Modell '{model}'")
    payload = {
        "model": model,
        "prompt": build_prompt(pdf_path.name, extracted_text),
        "stream": False,
        "format": "json",
        "options": {
            "temperature": 0.2,
        },
    }
    encoded = json.dumps(payload).encode("utf-8")
    http_request = request.Request(
        ollama_url,
        data=encoded,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        print("  [ollama] Warte auf Antwort...")
        with request.urlopen(http_request, timeout=180) as response:
            body = response.read().decode("utf-8")
        print(f"  [ollama] Antwort erhalten ({len(body)} Bytes)")
    except error.URLError as exc:
        raise RuntimeError(f"Ollama nicht erreichbar unter {ollama_url}: {exc}") from exc

    if verbose:
        print(f"  [ollama] Rohantwort: {body[:1000]}")

    try:
        outer = json.loads(body)
        raw = outer.get("response") or outer.get("thinking", "")
        if not raw:
            raise RuntimeError(
                f"Felder 'response' und 'thinking' sind leer für {pdf_path.name}: {body}"
            )
        if raw != outer.get("response"):
            print(f"  [ollama] 'response' war leer, verwende 'thinking'-Feld")
        inner = json.loads(raw)
        print(f"  [ollama] Geparstes JSON: {inner}")
        date = sanitize_date(inner.get("date", "0000-00-00"))
        doc_type = sanitize_segment(inner.get("doc_type", "Dokument"))
        keywords = sanitize_keywords(inner.get("keywords", "unbekannt"))
        print(f"  [ollama] date={date!r}, doc_type={doc_type!r}, keywords={keywords!r}")
    except (KeyError, json.JSONDecodeError, TypeError) as exc:
        raise RuntimeError(
            f"Unerwartete Antwort von Ollama für {pdf_path.name}: {body}"
        ) from exc

    filename = build_filename(date, doc_type, keywords)
    print(f"  [ollama] Vorgeschlagener Dateiname: {filename!r}")
    return filename


def ensure_unique_path(target: Path) -> Path:
    if not target.exists():
        return target
    stem = target.stem
    suffix = target.suffix
    counter = 2
    while True:
        candidate = target.with_name(f"{stem}-{counter}{suffix}")
        if not candidate.exists():
            return candidate
        counter += 1


def rename_pdf(
    pdf_path: Path,
    *,
    model: str,
    ollama_url: str,
    dry_run: bool,
    max_pages: int,
    max_chars: int,
    verbose: bool = False,
) -> RenameResult:
    print(f"\n--- Verarbeite: {pdf_path.name} ---")
    extracted_text = extract_pdf_text(
        pdf_path, max_pages=max_pages, max_chars=max_chars, verbose=verbose
    )
    if not extracted_text:
        print("  [skip] Kein extrahierbarer Text gefunden")
        return RenameResult(source=pdf_path, target=None, reason="kein extrahierbarer Text")

    suggested_name = request_filename_from_ollama(
        pdf_path=pdf_path,
        extracted_text=extracted_text,
        model=model,
        ollama_url=ollama_url,
        verbose=verbose,
    )
    target_path = pdf_path.with_name(f"{suggested_name}.pdf")

    if target_path == pdf_path:
        print("  [skip] Datei hat bereits den vorgeschlagenen Namen")
        return RenameResult(
            source=pdf_path, target=pdf_path, reason="bereits korrekt benannt"
        )

    target = ensure_unique_path(target_path)

    if not dry_run:
        print(f"  [rename] {pdf_path.name} -> {target.name}")
        pdf_path.rename(target)
    else:
        print(f"  [dry-run] Würde umbenennen: {pdf_path.name} -> {target.name}")
    return RenameResult(
        source=pdf_path, target=target, reason="umbenannt" if not dry_run else "dry-run"
    )


def iter_results(args: argparse.Namespace) -> Iterable[RenameResult]:
    source_path = Path(args.path).expanduser().resolve()
    if not source_path.exists():
        raise FileNotFoundError(f"Pfad existiert nicht: {source_path}")

    pdf_files = discover_pdfs(source_path, recursive=args.recursive)
    if not pdf_files:
        raise FileNotFoundError(f"Keine PDF-Dateien gefunden unter: {source_path}")

    print(f"[info] {len(pdf_files)} PDF(s) gefunden in {source_path}")
    print(f"[info] Modell: {args.model}")
    print(f"[info] Ollama-URL: {args.ollama_url}")
    print(f"[info] Dry-run: {args.dry_run}")
    for i, pdf_path in enumerate(pdf_files, start=1):
        print(f"\n[{i}/{len(pdf_files)}] {pdf_path.name}")
        try:
            yield rename_pdf(
                pdf_path,
                model=args.model,
                ollama_url=args.ollama_url,
                dry_run=args.dry_run,
                max_pages=args.max_pages,
                max_chars=args.max_chars,
                verbose=args.verbose,
            )
        except Exception as exc:
            print(f"  [error] {pdf_path.name}: {exc}")
            yield RenameResult(source=pdf_path, target=None, reason=str(exc), is_error=True)


def main() -> int:
    args = parse_args()
    failures = 0

    try:
        for result in iter_results(args):
            if result.target is None:
                failures += 1
                if result.is_error:
                    print(f"FEHLER        {result.source.name}: {result.reason}")
                else:
                    print(f"ÜBERSPRUNGEN  {result.source.name}: {result.reason}")
                continue

            if args.verbose:
                print(f"INFO  {result.source} -> {result.target}")
            else:
                print(
                    f"OK    {result.source.name} -> {result.target.name} ({result.reason})"
                )
    except Exception as exc:
        print(f"FEHLER {exc}", file=sys.stderr)
        return 1

    return 2 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
