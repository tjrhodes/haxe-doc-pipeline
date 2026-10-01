package docpipe;

import sys.io.File;
import sys.FileSystem;
import haxe.Template;

/**
 * Pdf - PDF utilities using external tools
 * 
 * Provides Promise-based wrappers for common PDF operations:
 * - Page counting (pdfinfo)
 * - Merging (pdfunite)
 * - HTML to PDF conversion (weasyprint)
 * - Document to PDF conversion (LibreOffice)
 * - Stamping/watermarking (pdftk)
 */
class Pdf {
    /**
     * Count the number of pages in a PDF file.
     * Uses pdfinfo from poppler-utils.
     */
    public static function countPages(pdfPath:String):Int {
        if (!FileSystem.exists(pdfPath)) {
            return 0;
        }
        
        // Use pdfinfo and parse output
        var timestamp = Std.int(Date.now().getTime());
        var tempFile = '/tmp/pdfinfo_$timestamp.txt';
        
        // Run pdfinfo and redirect to temp file
        var exitCode = Sys.command('pdfinfo "$pdfPath" > "$tempFile" 2>/dev/null');
        
        if (exitCode != 0 || !FileSystem.exists(tempFile)) {
            return 0;
        }
        
        var output = File.getContent(tempFile);
        FileSystem.deleteFile(tempFile);
        
        // Parse "Pages: X" from output
        var lines = output.split('\n');
        for (line in lines) {
            if (StringTools.startsWith(StringTools.trim(line), 'Pages:')) {
                var parts = line.split(':');
                if (parts.length >= 2) {
                    var pageStr = StringTools.trim(parts[1]);
                    var count = Std.parseInt(pageStr);
                    return count != null ? count : 0;
                }
            }
        }
        
        return 0;
    }

    /**
     * Merge multiple PDF files into a single output file.
     * Uses pdfunite from poppler-utils.
     * @return true on success, false on failure
     */
    public static function merge(inputPaths:Array<String>, outputPath:String):Bool {
        if (inputPaths.length == 0) {
            return false;
        }
        
        if (inputPaths.length == 1) {
            // Just copy the single file
            File.copy(inputPaths[0], outputPath);
            return true;
        }
        
        var args = inputPaths.copy();
        args.push(outputPath);
        var exitCode = Sys.command('pdfunite', args);
        return exitCode == 0;
    }

    /**
     * Convert HTML file to PDF using WeasyPrint.
     * @param htmlPath Path to HTML file
     * @param outputPath Path for output PDF
     * @param cssPath Optional CSS file path
     * @return true on success, false on failure
     */
    public static function fromHtml(htmlPath:String, outputPath:String, ?cssPath:String):Bool {
        var args:Array<String> = [];
        if (cssPath != null) {
            args.push('-s');
            args.push(cssPath);
        }
        args.push(htmlPath);
        args.push(outputPath);
        
        var exitCode = Sys.command('weasyprint', args);
        return exitCode == 0;
    }

    /**
     * Convert HTML string to PDF.
     * Saves HTML to temp file, converts, then cleans up.
     * @param html HTML content string
     * @param outputPath Path for output PDF
     * @param cssPath Optional CSS file path
     * @return true on success, false on failure
     */
    public static function fromHtmlString(html:String, outputPath:String, ?cssPath:String):Bool {
        var timestamp = Std.int(Date.now().getTime());
        var tempHtmlPath = '/tmp/html_$timestamp.html';
        
        File.saveContent(tempHtmlPath, html);
        var result = fromHtml(tempHtmlPath, outputPath, cssPath);
        
        if (FileSystem.exists(tempHtmlPath)) {
            FileSystem.deleteFile(tempHtmlPath);
        }
        
        return result;
    }

    /**
     * Convert a document to PDF using LibreOffice headless mode.
     * Supports: doc, docx, odt, rtf, txt, csv, xls, xlsx, ods, ppt, pptx, odp
     * CSV files are handled specially via HTML table conversion (LibreOffice can't open CSV in headless).
     * @param inputPath Path to document
     * @param outputDir Directory for output PDF
     * @return Path to converted PDF, or null on failure
     */
    public static function fromDocument(inputPath:String, outputDir:String):Null<String> {
        if (!FileSystem.exists(inputPath)) {
            return null;
        }
        
        // CSV needs special handling — LibreOffice headless can't open CSV without interactive dialog
        var fileParts = inputPath.split('/');
        var fname = fileParts[fileParts.length - 1];
        var extParts = fname.split('.');
        var ext = extParts.length > 1 ? extParts[extParts.length - 1].toLowerCase() : '';
        if (ext == 'csv') {
            return fromCsv(inputPath, outputDir);
        }
        
        // Generate unique temp name to avoid collisions
        var parts = inputPath.split('/');
        var filename = parts[parts.length - 1];
        var timestamp = Std.int(Date.now().getTime());
        var uniqueName = 'doc_${timestamp}_${filename}';
        
        // Copy to output dir with unique name
        var tempPath = outputDir + '/' + uniqueName;
        File.copy(inputPath, tempPath);
        
        // Use unique user profile to avoid conflicts
        var userProfile = '-env:UserInstallation=file:///tmp/libreoffice_headless_$timestamp';
        var exitCode = Sys.command('soffice', [userProfile, '--headless', '--convert-to', 'pdf', '--outdir', outputDir, tempPath]);
        
        // Clean up temp copy
        if (FileSystem.exists(tempPath)) {
            FileSystem.deleteFile(tempPath);
        }
        
        if (exitCode != 0) {
            return null;
        }
        
        // Get output filename (same base name but .pdf extension)
        var nameParts = uniqueName.split('.');
        nameParts[nameParts.length - 1] = 'pdf';
        var pdfFilename = nameParts.join('.');
        var pdfPath = outputDir + '/' + pdfFilename;
        
        if (!FileSystem.exists(pdfPath)) {
            return null;
        }
        
        return pdfPath;
    }
    
    /**
     * Convert a CSV file to PDF via HTML table + weasyprint.
     * LibreOffice headless can't open CSV (needs interactive separator dialog).
     */
    public static function fromCsv(inputPath:String, outputDir:String):Null<String> {
        if (!FileSystem.exists(inputPath)) {
            return null;
        }
        
        var content = File.getContent(inputPath);
        var lines = content.split('\n');
        
        // Build HTML table
        var rows = new StringBuf();
        var isHeader = true;
        for (line in lines) {
            var trimmed = StringTools.trim(line);
            if (trimmed.length == 0) continue;
            
            var cells = trimmed.split(',');
            var tag = isHeader ? 'th' : 'td';
            rows.add('<tr>');
            for (cell in cells) {
                rows.add('<$tag>${StringTools.htmlEscape(StringTools.trim(cell))}</$tag>');
            }
            rows.add('</tr>\n');
            isHeader = false;
        }
        
        var html = '<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
  body { font-family: sans-serif; font-size: 11pt; margin: 20mm; }
  table { border-collapse: collapse; width: 100%; }
  th, td { border: 1px solid #333; padding: 6px 10px; text-align: left; }
  th { background: #e0e0e0; font-weight: bold; }
  tr:nth-child(even) td { background: #f5f5f5; }
</style></head><body>
<table>\n${rows.toString()}</table>\n</body></html>';
        
        var timestamp = Std.int(Date.now().getTime());
        var htmlPath = outputDir + '/csv_${timestamp}.html';
        var pdfPath = outputDir + '/csv_${timestamp}.pdf';
        
        File.saveContent(htmlPath, html);
        
        var exitCode = Sys.command('weasyprint', [htmlPath, pdfPath]);
        
        // Clean up HTML
        if (FileSystem.exists(htmlPath)) {
            FileSystem.deleteFile(htmlPath);
        }
        
        if (exitCode != 0 || !FileSystem.exists(pdfPath)) {
            return null;
        }
        
        return pdfPath;
    }

    /**
     * Apply a stamp/watermark overlay to each page of a PDF.
     * Uses pdftk multistamp command.
     * @param pdfPath Original PDF
     * @param stampPdfPath Stamp PDF (each page applied to corresponding original page)
     * @param outputPath Output PDF path
     * @return true on success, false on failure
     */
    public static function applyStamp(pdfPath:String, stampPdfPath:String, outputPath:String):Bool {
        var exitCode = Sys.command('pdftk', [pdfPath, 'multistamp', stampPdfPath, 'output', outputPath]);
        return exitCode == 0;
    }

    /**
     * Generate a multi-page footer overlay PDF for stamping onto a document.
     * Creates one page per original page with consistent footer layout.
     * @param pageCount Number of pages in original document
     * @param footerData Data for footer content (section, name, fromEmail, filename)
     * @param outputDir Directory for output PDF
     * @return Path to footer PDF, or null on failure
     */
    public static function generateFooterOverlay(pageCount:Int, footerData:FooterData, outputDir:String):Null<String> {
        var timestamp = Std.int(Date.now().getTime());
        var footerHtmlPath = '$outputDir/footer_overlay_$timestamp.html';
        var footerPdfPath = '$outputDir/footer_overlay_$timestamp.pdf';
        
        var section = footerData.section != null ? footerData.section : 'N/A';
        var name = footerData.name != null ? footerData.name : 'Unknown';
        var fromEmail = footerData.fromEmail != null ? footerData.fromEmail : 'Unknown';
        var filename = footerData.filename != null ? footerData.filename : 'Attachment';
        
        // Build multi-page HTML
        var buf = new StringBuf();
        buf.add('<!DOCTYPE html><html><head><meta charset="UTF-8"><style>');
        buf.add('@page { size: A4; margin: 0; }');
        buf.add('body { margin: 0; padding: 0; font-family: "Roboto Condensed", "Arial Narrow", Arial, sans-serif; }');
        buf.add('.page { width: 210mm; height: 297mm; position: relative; page-break-after: always; }');
        buf.add('.page:last-child { page-break-after: avoid; }');
        buf.add('.footer { position: absolute; bottom: 8mm; left: 15mm; right: 15mm; height: 10mm; ');
        buf.add('display: flex; justify-content: space-between; align-items: center; ');
        buf.add('font-size: 9pt; color: #333; border-top: 0.5pt solid #ccc; padding-top: 2mm; }');
        buf.add('.footer-left { text-align: left; }');
        buf.add('.footer-center { text-align: center; flex: 1; padding: 0 10mm; }');
        buf.add('.footer-right { text-align: right; }');
        buf.add('.label { font-weight: bold; color: #666; }');
        buf.add('</style></head><body>');
        
        for (i in 1...(pageCount + 1)) {
            buf.add('<div class="page"><div class="footer">');
            buf.add('<div class="footer-left">$section - $name</div>');
            buf.add('<div class="footer-center"><span class="label">From:</span> $fromEmail &bull; ');
            buf.add('<span class="label">File:</span> $filename</div>');
            buf.add('<div class="footer-right">$i / $pageCount</div>');
            buf.add('</div></div>');
        }
        
        buf.add('</body></html>');
        
        // Save HTML and convert to PDF
        File.saveContent(footerHtmlPath, buf.toString());
        var exitCode = Sys.command('weasyprint', [footerHtmlPath, footerPdfPath]);
        
        // Clean up HTML
        if (FileSystem.exists(footerHtmlPath)) {
            FileSystem.deleteFile(footerHtmlPath);
        }
        
        if (exitCode != 0) {
            return null;
        }
        
        return footerPdfPath;
    }

    /**
     * Apply footer to a PDF and return the stamped version.
     * Combines generateFooterOverlay + applyStamp + cleanup.
     * @param pdfPath Original PDF to stamp
     * @param footerData Data for footer content
     * @param outputDir Directory for output
     * @return Path to stamped PDF, or null on failure
     */
    public static function applyFooterToPdf(pdfPath:String, footerData:FooterData, outputDir:String):Null<String> {
        var pageCount = countPages(pdfPath);
        if (pageCount <= 0) pageCount = 1;
        
        var footerPdfPath = generateFooterOverlay(pageCount, footerData, outputDir);
        if (footerPdfPath == null) {
            return null;
        }
        
        // Generate output path
        var pdfPathParts = pdfPath.split('/');
        var originalFilename = pdfPathParts[pdfPathParts.length - 1];
        var timestamp = Std.int(Date.now().getTime());
        var stampedFilename = 'stamped_${timestamp}_$originalFilename';
        var stampedPdfPath = '$outputDir/$stampedFilename';
        
        var success = applyStamp(pdfPath, footerPdfPath, stampedPdfPath);
        
        // Clean up footer PDF
        if (FileSystem.exists(footerPdfPath)) {
            FileSystem.deleteFile(footerPdfPath);
        }
        
        return success ? stampedPdfPath : null;
    }

    /**
     * Check if a file extension is a convertible document type.
     * @return true if LibreOffice can convert this type to PDF
     */
    public static function isConvertibleDocument(ext:String):Bool {
        var convertibleExts = ['doc', 'docx', 'odt', 'rtf', 'txt', 'csv', 'xls', 'xlsx', 'ods', 'ppt', 'pptx', 'odp'];
        return convertibleExts.indexOf(ext.toLowerCase()) > -1;
    }

    /**
     * Check if a file extension is an image type that can be embedded.
     */
    public static function isImage(ext:String):Bool {
        var imageExts = ['jpg', 'jpeg', 'png', 'gif'];
        return imageExts.indexOf(ext.toLowerCase()) > -1;
    }

    /**
     * Create a ZIP file from a list of PDF files.
     * Uses the zip command.
     * @param pdfPaths Array of PDF file paths
     * @param outputPath Path for output ZIP file
     * @return true on success, false on failure
     */
    public static function createZip(filePaths:Array<String>, outputPath:String):Bool {
        var args = ['-j', outputPath];
        for (path in filePaths) {
            args.push(path);
        }
        var exitCode = Sys.command('zip', args);
        return exitCode == 0;
    }
}

typedef FooterData = {
    ?section:String,
    ?name:String,
    ?fromEmail:String,
    ?filename:String
}
