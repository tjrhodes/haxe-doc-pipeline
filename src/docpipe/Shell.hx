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
    
    private static function mergeOptions(?options:ExecOptions):ExecOptions {
        if (options == null) return defaultOptions;
        return {
            maxBuffer: options.maxBuffer != null ? options.maxBuffer : defaultOptions.maxBuffer,
            timeout: options.timeout != null ? options.timeout : defaultOptions.timeout,
            cwd: options.cwd,
            env: options.env,
            encoding: options.encoding,
            shell: options.shell
        };
    }
}
