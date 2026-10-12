package docpipe;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/**
 * PDF utilities built on command-line tools.
 *
 *   pdfinfo, pdfunite   (poppler-utils)  page counts, merging
 *   weasyprint          (pip)            HTML to PDF
 *   soffice             (LibreOffice)    Office documents to PDF
 *   pdftk               (pdftk-java)     stamping one PDF onto another
 *   zip                                  zipping files together
 *
 * Every tool is run with its arguments passed separately, never through a shell,
 * so file names with spaces or quotes in them are safe.
 */
class Pdf {
    /** Extensions LibreOffice can turn into a PDF (CSV goes through `fromCsv` instead). */
    static final CONVERTIBLE = ['doc', 'docx', 'odt', 'rtf', 'txt', 'csv', 'xls', 'xlsx', 'ods', 'ppt', 'pptx', 'odp'];

    /** Image extensions that can be embedded in an HTML page as they are. */
    static final IMAGES = ['jpg', 'jpeg', 'png', 'gif'];

    /** Counts files made in this process, so two made in the same millisecond still get different names. */
    static var made = 0;

    /** The number of pages in a PDF, read with pdfinfo; 0 if the file is missing or unreadable. */
    public static function countPages(pdfPath:String):Int {
        if (!FileSystem.exists(pdfPath)) return 0;
        try {
            var info:String = js.node.ChildProcess.execFileSync('pdfinfo', [pdfPath], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
            var pages = ~/^Pages:\s+(\d+)/m;
            return pages.match(info) ? Std.parseInt(pages.matched(1)) : 0;
        } catch (_:Dynamic) {
            return 0;
        }
    }

    /** Join PDFs into one with pdfunite. A single input is simply copied. */
    public static function merge(inputPaths:Array<String>, outputPath:String):Bool {
        if (inputPaths.length == 0) return false;
        if (inputPaths.length == 1) {
            File.copy(inputPaths[0], outputPath);
            return true;
        }
        return run('pdfunite', inputPaths.concat([outputPath]));
    }

    /** Render an HTML file to PDF with WeasyPrint, with an optional extra stylesheet. */
    public static function fromHtml(htmlPath:String, outputPath:String, ?cssPath:String):Bool {
        var style = cssPath != null ? ['-s', cssPath] : [];
        return run('weasyprint', style.concat([htmlPath, outputPath]));
    }

    /** Render an HTML string to PDF: written to a temporary file, rendered, then the file is removed. */
    public static function fromHtmlString(html:String, outputPath:String, ?cssPath:String):Bool {
        var htmlPath = tempPath(js.node.Os.tmpdir(), 'html', 'html');
        File.saveContent(htmlPath, html);
        var ok = fromHtml(htmlPath, outputPath, cssPath);
        remove(htmlPath);
        return ok;
    }

    /**
     * Convert an Office document (or plain text) to PDF with LibreOffice, headless.
     * CSV goes through `fromCsv`, because LibreOffice headless can't open CSV without its import dialog.
     * @return the new PDF's path in `outputDir`, or null on failure
     */
    public static function fromDocument(inputPath:String, outputDir:String):Null<String> {
        if (!FileSystem.exists(inputPath)) return null;
        if (Path.extension(inputPath).toLowerCase() == 'csv') return fromCsv(inputPath, outputDir);
        var copy = tempPath(outputDir, 'doc', Path.withoutDirectory(inputPath));   // unique name, so outputs never clash
        File.copy(inputPath, copy);
        var profile = '-env:UserInstallation=file://' + tempPath(js.node.Os.tmpdir(), 'libreoffice', 'profile');
        var ok = run('soffice', [profile, '--headless', '--convert-to', 'pdf', '--outdir', outputDir, copy]);
        remove(copy);
        var pdfPath = Path.withExtension(copy, 'pdf');
        return ok && FileSystem.exists(pdfPath) ? pdfPath : null;
    }

    /** Convert a CSV file to PDF as a table: the first row is the header. @return the PDF's path, or null */
    public static function fromCsv(inputPath:String, outputDir:String):Null<String> {
        if (!FileSystem.exists(inputPath)) return null;
        var rows = Csv.parse(File.getContent(inputPath)).map(cells -> cells.map(escape));
        var body = [for (i in 0...rows.length) tableRow(rows[i], i == 0 ? 'th' : 'td')].join('\n');
        var pdfPath = tempPath(outputDir, 'csv', 'pdf');
        return fromHtmlString(page(CSV_STYLE, '<table>\n$body\n</table>'), pdfPath) ? pdfPath : null;
    }

    /** Stamp each page of `stampPdfPath` onto the matching page of `pdfPath`, with pdftk. */
    public static function applyStamp(pdfPath:String, stampPdfPath:String, outputPath:String):Bool {
        return run('pdftk', [pdfPath, 'multistamp', stampPdfPath, 'output', outputPath]);
    }

    /**
     * A PDF of `pageCount` blank A4 pages, each with a footer: section and name, sender, file name, page number.
     * The values are escaped, so text from an email (an address in angle brackets, say) prints as written
     * and can never add markup, or make WeasyPrint load a file, of its own.
     * @return the footer PDF's path in `outputDir`, or null on failure
     */
    public static function generateFooterOverlay(pageCount:Int, footerData:FooterData, outputDir:String):Null<String> {
        var text = footerText(footerData);
        var pages = [for (i in 1...pageCount + 1) footerPage(text, '$i / $pageCount')].join('\n');
        var pdfPath = tempPath(outputDir, 'footer_overlay', 'pdf');
        return fromHtmlString(page(FOOTER_STYLE, pages), pdfPath) ? pdfPath : null;
    }

    /** Stamp a footer onto every page of a PDF (see `generateFooterOverlay`). @return the stamped PDF's path, or null */
    public static function applyFooterToPdf(pdfPath:String, footerData:FooterData, outputDir:String):Null<String> {
        var footerPdfPath = generateFooterOverlay(Std.int(Math.max(1, countPages(pdfPath))), footerData, outputDir);
        if (footerPdfPath == null) return null;
        var stampedPath = tempPath(outputDir, 'stamped', Path.withoutDirectory(pdfPath));
        var ok = applyStamp(pdfPath, footerPdfPath, stampedPath);
        remove(footerPdfPath);
        return ok ? stampedPath : null;
    }

    /** True if LibreOffice can convert files with this extension to PDF. */
    public static function isConvertibleDocument(ext:String):Bool {
        return CONVERTIBLE.contains(ext.toLowerCase());
    }

    /** True if files with this extension are images that can be embedded as they are. */
    public static function isImage(ext:String):Bool {
        return IMAGES.contains(ext.toLowerCase());
    }

    /** Zip files together, without their folders (`zip -j`). */
    public static function createZip(filePaths:Array<String>, outputPath:String):Bool {
        return run('zip', ['-j', outputPath].concat(filePaths));
    }

    //───────────────────────────────────────────────────────────
    // HTML for the generated pages
    //───────────────────────────────────────────────────────────

    static final CSV_STYLE = 'body { font-family: sans-serif; font-size: 11pt; margin: 20mm; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #333; padding: 6px 10px; text-align: left; }
th { background: #e0e0e0; font-weight: bold; }
tr:nth-child(even) td { background: #f5f5f5; }';

    static final FOOTER_STYLE = '@page { size: A4; margin: 0; }
body { margin: 0; font-family: "Roboto Condensed", "Arial Narrow", Arial, sans-serif; }
.page { width: 210mm; height: 297mm; position: relative; page-break-after: always; }
.page:last-child { page-break-after: avoid; }
.footer { position: absolute; bottom: 8mm; left: 15mm; right: 15mm; height: 10mm; display: flex;
  justify-content: space-between; align-items: center; font-size: 9pt; color: #333;
  border-top: 0.5pt solid #ccc; padding-top: 2mm; }
.footer-center { text-align: center; flex: 1; padding: 0 10mm; }
.label { font-weight: bold; color: #666; }';

    /** A whole HTML document from a stylesheet and a body. */
    static function page(css:String, body:String):String {
        return '<!DOCTYPE html><html><head><meta charset="utf-8"><style>\n$css\n</style></head><body>\n$body\n</body></html>';
    }

    /** One table row, every cell in the given tag (th or td). The cells must already be escaped. */
    static function tableRow(cells:Array<String>, tag:String):String {
        return '<tr>' + cells.map(cell -> '<$tag>$cell</$tag>').join('') + '</tr>';
    }

    /** The three parts of a footer, escaped, with defaults for anything missing. */
    static function footerText(data:FooterData):{left:String, centre:String} {
        inline function or(value:Null<String>, fallback:String) return escape(value != null ? value : fallback);
        return {
            left: or(data.section, 'N/A') + ' - ' + or(data.name, 'Unknown'),
            centre: '<span class="label">From:</span> ' + or(data.fromEmail, 'Unknown')
                + ' &bull; <span class="label">File:</span> ' + or(data.filename, 'Attachment'),
        };
    }

    /** One page of the footer overlay. */
    static function footerPage(text:{left:String, centre:String}, number:String):String {
        return '<div class="page"><div class="footer"><div>${text.left}</div>'
            + '<div class="footer-center">${text.centre}</div><div>$number</div></div></div>';
    }

    //───────────────────────────────────────────────────────────
    // Small helpers
    //───────────────────────────────────────────────────────────

    /** Text made safe to put inside HTML, quotes included. */
    static function escape(text:String):String {
        return StringTools.htmlEscape(text, true);
    }

    /** Run a tool with its arguments (no shell). True if it exited with 0. */
    static function run(tool:String, args:Array<String>):Bool {
        return Sys.command(tool, args) == 0;
    }

    /** A new, unused path in `dir`: `<prefix>_<time>_<count>_<name>`, where `name` is an extension or a file name. */
    static function tempPath(dir:String, prefix:String, name:String):String {
        var file = name.indexOf('.') >= 0 ? name : 'file.$name';
        return Path.join([dir, '${prefix}_${Date.now().getTime()}_${made++}_$file']);
    }

    /** Delete a file if it is there. */
    static function remove(path:String):Void {
        if (FileSystem.exists(path)) FileSystem.deleteFile(path);
    }
}

typedef FooterData = {
    ?section:String,
    ?name:String,
    ?fromEmail:String,
    ?filename:String
}
