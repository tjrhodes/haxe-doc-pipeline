package docpipe;

import js.lib.Promise;
import js.node.Fs;
import js.node.Os;
import docpipe.Shell;
import docpipe.Log;

using StringTools;

/**
 * QR code reader using zbarimg + ImageMagick.
 * Crops image corners for fast scanning, falls back to full image.
 */
class QrScanner {

    /** Size in px of each corner crop. Most printed QR codes sit in a corner. */
    public static var cornerSize = 300;

    /** Scan an image file for QR codes. Returns decoded text or null. */
    public static function scan(filePath:String):Promise<Null<String>> {
        return getImageSize(filePath)
            .then(size -> scanCorners(filePath, size))
            .then(result -> result != null ? cast Promise.resolve(result) : scanFull(filePath))
            .catchError(e -> {
                Log.error('Error processing image', { file: filePath, error: Std.string(e) });
                return cast Promise.resolve(null);
            });
    }

    //───────────────────────────────────────────────────────────
    // Image dimensions
    //───────────────────────────────────────────────────────────

    static function getImageSize(filePath:String):Promise<{w:Int, h:Int}> {
        return Shell.exec('identify -format "%w %h" \'${filePath}\'')
            .then(r -> {
                var parts = r.stdout.trim().split(' ');
                return { w: Std.parseInt(parts[0]), h: Std.parseInt(parts[1]) };
            });
    }

    //───────────────────────────────────────────────────────────
    // Corner scanning — check 4 corners in priority order
    //───────────────────────────────────────────────────────────

    static function scanCorners(filePath:String, size:{w:Int, h:Int}):Promise<Null<String>> {
        var corners = buildCornerRegions(size.w, size.h);
        return scanCornerList(filePath, corners, 0);
    }

    /** Recursively try each corner until QR found or exhausted */
    static function scanCornerList(filePath:String, corners:Array<Corner>, idx:Int):Promise<Null<String>> {
        if (idx >= corners.length) return Promise.resolve(null);

        var c = corners[idx];
        var tmp = Os.tmpdir() + '/crop-' + Date.now().getTime() + '-' + c.name + '.png';

        return cropImage(filePath, c.crop, tmp)
            .then(_ -> readQr(tmp))
            .then(result -> {
                cleanup(tmp);
                return result != null
                    ? cast Promise.resolve(result)
                    : scanCornerList(filePath, corners, idx + 1);
            })
            .catchError(_ -> {
                cleanup(tmp);
                return scanCornerList(filePath, corners, idx + 1);
            });
    }

    //───────────────────────────────────────────────────────────
    // Full-image fallback
    //───────────────────────────────────────────────────────────

    static function scanFull(filePath:String):Promise<Null<String>> {
        return readQr(filePath).catchError(_ -> cast Promise.resolve(null));
    }

    //───────────────────────────────────────────────────────────
    // Low-level: crop, read QR, cleanup
    //───────────────────────────────────────────────────────────

    static function cropImage(src:String, geometry:String, dest:String):Promise<Void> {
        return Shell.exec('convert \'${src}\' -crop ${geometry} \'${dest}\'').then(_ -> null);
    }

    static function readQr(path:String):Promise<Null<String>> {
        return Shell.exec('zbarimg --quiet --raw \'${path}\'')
            .then(r -> {
                var data = r.stdout.trim();
                return data.length > 0 ? data : null;
            })
            .catchError(e -> {
                // Exit code 4 = no barcode found (expected)
                return cast Promise.resolve(null);
            });
    }

    static function cleanup(path:String):Void {
        try { Fs.unlinkSync(path); } catch (_:Dynamic) {}
    }

    //───────────────────────────────────────────────────────────
    // Corner geometry
    //───────────────────────────────────────────────────────────

    static function buildCornerRegions(w:Int, h:Int):Array<Corner> {
        var s = cornerSize;
        return [
            { crop: '${s}x${s}+${w - s}+${h - s}', name: 'bottom-right' },
            { crop: '${s}x${s}+${w - s}+0',         name: 'top-right' },
            { crop: '${s}x${s}+0+0',                name: 'top-left' },
            { crop: '${s}x${s}+0+${h - s}',         name: 'bottom-left' },
        ];
    }
}

private typedef Corner = {
    var crop:String;
    var name:String;
}
