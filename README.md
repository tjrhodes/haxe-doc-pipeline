# docpipe — document pipeline helpers for Haxe on Node.js

A small toolkit for building print-and-scan workflows in [Haxe](https://haxe.org) targeting Node.js.
Turn HTML into PDFs, merge, stamp and count pages, and read QR codes from scanned paper.

It's extracted (and cleaned of anything client-specific) from a production system I built and
ran for over ten years: a secure email service for prisons in Italy. Incoming emails were rendered to PDF,
stamped with a footer, batched for printing, and handwritten replies came back as scans with a
QR code that routed each one to the right recipient.

## What's in it

| Module | What it does | Uses |
|---|---|---|
| `docpipe.Shell` | Promise-based `exec`, with env and working-directory variants | `child_process` |
| `docpipe.Pdf` | HTML → PDF, page count, merge, stamp/footer overlay, Office/CSV → PDF, zip | WeasyPrint, poppler-utils, pdftk, LibreOffice |
| `docpipe.QrScanner` | Finds a QR code on a scanned page, trying the four corners first (fast), then the whole image | ImageMagick, zbar |
| `docpipe.Log` | Timestamped, structured console logging with a per-service prefix | — |
| `docpipe.Timer` | `sleep`, `interval`, `delay` as promises/callbacks | — |

### Why corners first?

A scanned A4 page at 300 dpi is about 2,500 × 3,500 px. Running zbar on the whole page is slow
and gets confused by handwriting. Reply sheets carry their QR code in a corner, so cropping
four 300 px squares and scanning those first is much faster. The full page is the fallback.

## Quick start

```bash
# System tools
sudo apt install imagemagick zbar-tools poppler-utils pdftk-java
pip install weasyprint

# Haxe deps
haxelib install hxnodejs

# Build and run the examples
haxe build-examples.hxml
node bin/scan-folder.js ./scans        # print the QR code found on each image
node bin/html-to-pdf.js hello.pdf      # render HTML to PDF and count its pages
```

```haxe
import docpipe.Pdf;
import docpipe.QrScanner;

Pdf.fromHtmlString('<h1>Invoice</h1>', 'invoice.pdf');
trace(Pdf.countPages('invoice.pdf'));

QrScanner.scan('scan-001.png').then(code -> trace(code));   // null if none found
```

## Notes

- Requires Haxe 4.3+ and `hxnodejs`.
- The PDF helpers call command-line tools, so they run anywhere those tools are installed (Linux servers, CI).
- MIT licensed. Issues and pull requests welcome.
