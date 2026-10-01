import docpipe.QrScanner;
import docpipe.Log;
import js.node.Fs;
import js.lib.Promise;

/**
 * Scan every image in a folder for a QR code and print what was found.
 *
 *   haxe build-examples.hxml && node bin/scan-folder.js ./scans
 *
 * Needs ImageMagick (`identify`, `convert`) and zbar (`zbarimg`) on the PATH.
 */
class ScanFolder {
    static function main() {
        var dir = js.Node.process.argv[2];
        if (dir == null) { Log.error('Usage: node bin/scan-folder.js <folder>'); return; }
        Log.setService('scan-folder');

        var images = Fs.readdirSync(dir).filter(f -> ~/\.(png|jpe?g|tiff?)$/i.match(f));
        Log.info('Scanning ${images.length} images');

        // One at a time: zbar and ImageMagick are CPU-heavy
        var chain:Promise<Dynamic> = Promise.resolve(null);
        for (f in images) {
            var path = '$dir/$f';
            chain = chain.then(_ -> QrScanner.scan(path)).then(code -> {
                if (code != null) Log.info(f, { qr: code }) else Log.warn(f, { qr: null });
                return null;
            });
        }
        chain.then(_ -> Log.info('Done'));
    }
}
