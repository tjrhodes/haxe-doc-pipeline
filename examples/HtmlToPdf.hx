import docpipe.Pdf;
import docpipe.Log;

/**
 * Render an HTML string to PDF with WeasyPrint, then report its page count.
 *
 *   haxe build-examples.hxml && node bin/html-to-pdf.js out.pdf
 */
class HtmlToPdf {
    static function main() {
        var out = js.Node.process.argv[2] != null ? js.Node.process.argv[2] : 'example.pdf';
        var html = '<html><body style="font-family:sans-serif">'
            + '<h1>Hello from docpipe</h1><p>Generated with Haxe + WeasyPrint.</p>'
            + '</body></html>';

        if (Pdf.fromHtmlString(html, out)) {
            Log.info('Wrote PDF', { file: out, pages: Pdf.countPages(out) });
        } else {
            Log.error('WeasyPrint failed. Is it installed? (pip install weasyprint)');
        }
    }
}
