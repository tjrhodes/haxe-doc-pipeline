package docpipe;

using StringTools;

/**
 * Simple structured logging with timestamps.
 * Uses console.log directly to avoid Haxe trace file references.
 * 
 * Usage:
 *   Log.info("Starting service");
 *   Log.error("Failed to connect", { code: 500 });
 */
class Log {
    private static var serviceName:Null<String> = null;
    
    /** Set the service name for all log messages */
    public static function setService(name:String):Void {
        serviceName = name;
    }
    
    /** Info level log */
    public static function info(message:String, ?data:Dynamic):Void {
        log('INFO', message, data);
    }
    
    /** Warning level log */
    public static function warn(message:String, ?data:Dynamic):Void {
        log('WARN', message, data);
    }
    
    /** Error level log */
    public static function error(message:String, ?data:Dynamic):Void {
        log('ERROR', message, data);
    }
    
    /** Debug level log */
    public static function debug(message:String, ?data:Dynamic):Void {
        log('DEBUG', message, data);
    }
    
    /** Visual separator for startup/shutdown */
    public static function banner(title:String):Void {
        var line = '='.lpad('=', 45);
        print(line);
        print('  ${title}');
        print('  Started at ${Date.now().toString()}');
        print(line);
    }
    
    private static function log(level:String, message:String, ?data:Dynamic):Void {
        var prefix = serviceName != null ? '[${serviceName}] ' : '';
        var dataStr = data != null ? ' ' + haxe.Json.stringify(data) : '';
        print('${timestamp()} ${prefix}${level}: ${message}${dataStr}');
    }
    
    private static function timestamp():String {
        var now = Date.now();
        var h = Std.string(now.getHours()).lpad('0', 2);
        var m = Std.string(now.getMinutes()).lpad('0', 2);
        var s = Std.string(now.getSeconds()).lpad('0', 2);
        return '[${h}:${m}:${s}]';
    }
    
    private static inline function print(msg:String):Void {
        js.Syntax.code("console.log({0})", msg);
    }
}
