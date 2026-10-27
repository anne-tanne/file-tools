# File Tools

Kleine Mac-App, um Fotos und PDFs zu konvertieren, verkleinern und bearbeiten. Alles läuft lokal, nichts geht ins Internet.

Kann: Fotos konvertieren (JPG, PNG, HEIC, AVIF, TIFF), Fotos und PDFs komprimieren, Grösse ändern, drehen, Metadaten entfernen, Dateien umbenennen, PDFs zusammenfügen, aufteilen und Seiten umsortieren, Bilder aus PDFs ziehen, Word-Dokumente als PDF speichern.

Sprache: Deutsch, Englisch oder Französisch (Einstellungen, ⌘,).

## Voraussetzungen

- macOS 26 oder neuer
- Xcode oder die Command Line Tools (`xcode-select --install`) zum Bauen
- Für «Word to PDF»: Microsoft Word. Beim ersten Mal fragt macOS, ob die App Word steuern darf, das muss man erlauben.

## Bauen und installieren

```bash
git clone https://github.com/anne-tanne/file-tools.git
cd file-tools
./build.sh
mv "File Tools.app" /Applications/
```

Mit nur den Command Line Tools (ohne Xcode) funktioniert es auch, das App-Icon ist dann einfach flach statt Liquid Glass.

Die App ist nur ad-hoc signiert. Wer sie an mehrere Macs verteilt, signiert sie besser mit dem eigenen Developer-ID-Zertifikat.

## Update

```bash
git pull
./build.sh
```

Dann die alte App in `/Applications` ersetzen.

## Hinweis

Die App überschreibt nie Originale, sondern legt neue Dateien an (z. B. `Bild (compressed).jpg`). Einzige Ausnahme ist «Rename», das benennt direkt um (mit Rückgängig).

Fragen an Anne-Sophie Skarabis.
