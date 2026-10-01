package docpipe.externs;

/**
 * Extern for Node.js child_process module
 * @see https://nodejs.org/api/child_process.html
 */

@:jsRequire("child_process")
extern class ChildProcess {
    static function exec(command:String, ?options:ExecOptions, ?callback:ExecError->String->String->Void):Dynamic;
    static function execSync(command:String, ?options:ExecOptions):js.node.Buffer;
    static function spawn(command:String, ?args:Array<String>, ?options:SpawnOptions):ChildProcessHandle;
}

typedef ExecOptions = {
    @:optional var cwd:String;
    @:optional var env:Dynamic;
    @:optional var encoding:String;
    @:optional var shell:String;
    @:optional var timeout:Int;
    @:optional var maxBuffer:Int;
    @:optional var killSignal:String;
    @:optional var uid:Int;
    @:optional var gid:Int;
}

typedef SpawnOptions = {
    @:optional var cwd:String;
    @:optional var env:Dynamic;
    @:optional var detached:Bool;
    @:optional var shell:Bool;
    @:optional var stdio:Dynamic;
}

typedef ExecError = {
    @:optional var message:String;
    @:optional var code:Int;
    @:optional var killed:Bool;
    @:optional var signal:String;
}

extern class ChildProcessHandle {
    var stdout:Dynamic;
    var stderr:Dynamic;
    var pid:Int;
    function on(event:String, callback:Dynamic->Void):Void;
    function kill(?signal:String):Bool;
}
