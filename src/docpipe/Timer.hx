package docpipe;

import js.lib.Promise;

/**
 * Promise-based timing utilities.
 * 
 * Usage:
 *   @await Timer.sleep(1000); // Wait 1 second
 *   Timer.interval(60000, () -> checkSchedules());
 */
class Timer {
    
    /** Sleep for specified milliseconds */
    public static function sleep(ms:Int):Promise<Void> {
        return new Promise((resolve, _) -> {
            js.Syntax.code("setTimeout({0}, {1})", resolve, ms);
        });
    }
    
    /** Set up a recurring interval, returns cleanup function */
    public static function interval(ms:Int, callback:Void->Void):Void->Void {
        var id = js.Syntax.code("setInterval({0}, {1})", callback, ms);
        return () -> js.Syntax.code("clearInterval({0})", id);
    }
    
    /** Run once after delay */
    public static function delay(ms:Int, callback:Void->Void):Void {
        js.Syntax.code("setTimeout({0}, {1})", callback, ms);
    }
}
