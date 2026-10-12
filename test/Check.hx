import docpipe.*;
import docpipe.Pdf;
import js.lib.Promise;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/**
 * Checks every helper against the real tools. Needs everything from the README's Quick start.
 *
 *   haxe test.hxml && node bin/check.js
 *
 * Prints PASS or FAIL for each check and exits with 1 if any failed. Files go in a fresh folder under /tmp.
 */
class Check {
    static var dir:String;
    static var failures = 0;

    static function main() {
        dir = js.node.Fs.mkdtempSync(js.node.Path.join(js.node.Os.tmpdir(), 'docpipe-check-'));
        pdfChecks();
        csvChecks();
        shellChecks()
            .then(_ -> qrChecks())
            .then(_ -> finish());
    }

    /** Record one result. */
    static function check(name:String, passed:Bool, ?detail:Dynamic) {
        if (!passed) failures++;
        Sys.println((passed ? 'PASS  ' : 'FAIL  ') + name + (detail != null ? '   ($detail)' : ''));
    }

    /** The text of a PDF, read with pdftotext. */
    static function textOf(pdfPath:String):String {
        return js.node.ChildProcess.execFileSync('pdftotext', [pdfPath, '-'], { encoding: 'utf8' });
    }

    static function pdfChecks() {
        var two = '$dir/two pages.pdf';
        check('fromHtmlString', Pdf.fromHtmlString('<h1>One</h1><p style="break-before: page">Two</p>', two));
        check('countPages', Pdf.countPages(two) == 2, Pdf.countPages(two));
        check('countPages of a missing file is 0', Pdf.countPages('$dir/missing.pdf') == 0);
        File.saveContent('$dir/b.html', '<p>Bee</p>');
        File.saveContent('$dir/b.css', 'p { color: red }');
        check('fromHtml with a stylesheet', Pdf.fromHtml('$dir/b.html', '$dir/b.pdf', '$dir/b.css'));
        check('merge', Pdf.merge([two, '$dir/b.pdf'], '$dir/merged.pdf') && Pdf.countPages('$dir/merged.pdf') == 3);
        check('merge of one file copies it', Pdf.merge(['$dir/b.pdf'], '$dir/one.pdf') && FileSystem.exists('$dir/one.pdf'));
        footerChecks('$dir/merged.pdf');
        officeChecks(two);
    }

    static function footerChecks(pdfPath:String) {
        var data = { section: '2B', name: 'Mario Rossi', fromEmail: 'Lucia <lucia@example.it>', filename: "it's <b>a</b>.jpg" };
        var stamped = Pdf.applyFooterToPdf(pdfPath, data, dir);
        check('applyFooterToPdf keeps the page count', stamped != null && Pdf.countPages(stamped) == 3, stamped);
        var text = stamped != null ? textOf(stamped) : '';
        check('footer prints an address in angle brackets', text.contains('Lucia <lucia@example.it>'));
        check('footer prints markup as text', text.contains("it's <b>a</b>.jpg"));
        check('footer shows who and which page', text.contains('2B - Mario Rossi') && text.replace(' ', '').contains('3/3'));
    }

    static function officeChecks(pdfPath:String) {
        File.saveContent('$dir/note.txt', 'A plain text document');
        var doc = Pdf.fromDocument('$dir/note.txt', dir);
        check('fromDocument (LibreOffice)', doc != null && textOf(doc).contains('plain text'), doc);
        check('isConvertibleDocument', Pdf.isConvertibleDocument('DOCX') && !Pdf.isConvertibleDocument('exe'));
        check('isImage', Pdf.isImage('JPG') && !Pdf.isImage('pdf'));
        check('createZip', Pdf.createZip([pdfPath], '$dir/out.zip') && FileSystem.exists('$dir/out.zip'));
    }

    static function csvChecks() {
        var rows = Csv.parse('name,age\r\n"Rossi, Mario",41\n\n"She said ""hi""",  7 \n"two\nlines",9');
        check('Csv: quoted commas', rows[1][0] == 'Rossi, Mario', rows[1]);
        check('Csv: doubled quotes, blank lines skipped, cells trimmed', rows[2][0] == 'She said "hi"' && rows[2][1] == '7', rows[2]);
        check('Csv: line break inside quotes', rows[3][0] == 'two\nlines' && rows.length == 4, rows.length);
        File.saveContent('$dir/people.csv', 'name,age\n"Rossi, Mario",41\n');
        var pdf = Pdf.fromCsv('$dir/people.csv', dir);
        check('fromCsv', pdf != null && textOf(pdf).contains('Rossi, Mario'), pdf);
    }

    static function shellChecks():Promise<Dynamic> {
        return Promise.all([
            Shell.exec('echo hi').then(r -> check('Shell.exec', r.stdout.trim() == 'hi')),
            Shell.execIn('pwd', '/tmp').then(r -> check('Shell.execIn gives text', r.stdout.trim() == '/tmp', r.stdout)),
            Shell.execWithEnv('echo "$$FOO"', { FOO: 'bar' }).then(r -> check('Shell.execWithEnv gives text', r.stdout.trim() == 'bar', r.stdout)),
            Shell.exec('printf %s ' + Shell.quote("it's a test")).then(r -> check('Shell.quote', r.stdout == "it's a test", r.stdout)),
            Timer.sleep(20).then(_ -> check('Timer.sleep', true)),
        ]);
    }

    /** Each fixture and the code it should give (null: none). Scanned one after another: zbar is heavy. */
    static function qrChecks():Promise<Dynamic> {
        var expected = ["reply sheet's scan.png" => 'SHEET-OK', 'centre.png' => 'CENTRE-OK', 'small.png' => 'SMALL-OK', 'blank.png' => null];
        var chain:Promise<Dynamic> = Promise.resolve(null);
        for (file => code in expected) {
            chain = chain.then(_ -> QrScanner.scan('test/fixtures/$file')).then(found -> check('QrScanner: $file', found == code, found));
        }
        return chain.then(_ -> sheetCornerCheck());
    }

    /** The reply sheet's code must be found in its corner crop, not only by the slower whole-page fallback. */
    static function sheetCornerCheck():Promise<Dynamic> {
        var s = QrScanner.cornerSize, crop = '$dir/corner.png';
        var cut = 'convert ' + Shell.quote("test/fixtures/reply sheet's scan.png") + ' -gravity SouthEast -crop ${s}x$s+0+0 ' + crop;
        return Shell.exec('$cut && zbarimg --quiet --raw $crop')
            .then(r -> check('QR code fits in the bottom-right corner crop', r.stdout.trim() == 'SHEET-OK'),
                  _ -> check('QR code fits in the bottom-right corner crop', false));
    }

    static function finish() {
        Sys.println(failures == 0 ? '\nAll checks passed.' : '\n$failures check(s) failed.');
        Sys.exit(failures == 0 ? 0 : 1);
    }
}
