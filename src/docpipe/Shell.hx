package docpipe;

import js.lib.Promise;
import docpipe.externs.ChildProcess;
import docpipe.externs.ChildProcess.ExecOptions;

/**
 * Promise-based shell command execution.
 * Wraps child_process.exec for use with @await macros.
 * 
 * Usage:
 *   var result = @await Shell.exec("ls -la");
 *   trace(result.stdout);
 */

typedef ExecResult = {
    var stdout:String;
    var stderr:String;
}

typedef ExecError = {
    var message:String;
    var code:Int;
    var stdout:String;
    var stderr:String;
}

class Shell {
    
    /** Default options for most commands */
    private static var defaultOptions:ExecOptions = {
        maxBuffer: 10 * 1024 * 1024, // 10MB
        timeout: 0 // no timeout
    };
    
    /** Execute a shell command and return stdout/stderr */
    public static function exec(command:String, ?options:ExecOptions):Promise<ExecResult> {
        var opts = mergeOptions(options);
        
        return new Promise((resolve, reject) -> {
            ChildProcess.exec(command, opts, (error, stdout, stderr) -> {
                if (error != null) {
                    reject({
                        message: error.message != null ? error.message : 'Command failed',
                        code: error.code != null ? error.code : 1,
                        stdout: stdout != null ? stdout : '',
                        stderr: stderr != null ? stderr : ''
                    });
                } else {
                    resolve({
                        stdout: stdout != null ? stdout : '',
                        stderr: stderr != null ? stderr : ''
                    });
                }
            });
        });
    }
    
    /** Execute with environment variables */
    public static function execWithEnv(command:String, env:Dynamic):Promise<ExecResult> {
        // Merge with process.env
        var fullEnv = js.Syntax.code("{ ...process.env, ...{0} }", env);
        return exec(command, { env: fullEnv, maxBuffer: 10 * 1024 * 1024 });
    }
    
    /** Execute in specific directory */
    public static function execIn(command:String, cwd:String):Promise<ExecResult> {
        return exec(command, { cwd: cwd, maxBuffer: 10 * 1024 * 1024 });
    }
    
    /**
     * Put a value in single quotes for the shell, so spaces, quotes and other special characters in it
     * stay part of it: `ls ${Shell.quote(path)}`.
     */
    public static function quote(value:String):String {
        return "'" + value.split("'").join("'\\''") + "'";
    }

    /**
     * The default options with the caller's on top. Only options the caller actually set are copied:
     * passing Node an `encoding` of null makes it hand back raw bytes instead of text.
     */
    private static function mergeOptions(?options:ExecOptions):ExecOptions {
        var merged:ExecOptions = { maxBuffer: defaultOptions.maxBuffer, timeout: defaultOptions.timeout, encoding: 'utf8' };
        if (options == null) return merged;
        for (key in Reflect.fields(options)) {
            var value = Reflect.field(options, key);
            if (value != null) Reflect.setField(merged, key, value);
        }
        return merged;
    }
}
