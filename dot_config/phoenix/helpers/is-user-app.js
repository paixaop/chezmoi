/**
 * Check if a process with the given PID is still running.
 * @param {number} pid - The process ID to check.
 * @returns {boolean} - Returns true if the process is active, false otherwise.
 */
function isProcessActive(pid) {
    try {
        const task = Task.run("/bin/bash", ["-c", `ps -p ${pid}`], (task) => {
            // If task.output is empty, the process is not active
            return task.output.trim() !== "";
        });

        return !!task; // Return true if task exists
    } catch (error) {
        Phoenix.log(`Error checking process activity for PID ${pid}: ${error}`);
        return false; // Assume the process is not active on error
    }
}

/**
 * Checks if an app is a system app based on its executable path.
 * @param {App} app - The app to check.
 * @returns {boolean} - Returns true if the app is a system app, false otherwise.
 */
function isSystemPath(pid) {
    if (!pid) return false;

    try {
        const taskPath = Task.run("/bin/bash", ["-c", `ps -p ${pid} -o comm=`], (task) => {
            if(!task || !task.output ) return false;

            const path = task.output.trim();
            return path.startsWith('/System') || path.startsWith('/usr');
        });
    } catch (error) {
        Phoenix.log(`Error checking system path: ${error}`);
        return false;
    }
}

/**
 * Dynamically filter to determine if a window belongs to a user-facing app.
 * @param {Window} window - The window to check.
 * @returns {boolean} - Returns true if it's a user-facing app, false otherwise.
 */
function isUserApp(window) { 
    try {
        if(!window) return false;
        
        const app = window.app();
        if( !app ) return false;

        const appName = app.name();
        const bundleId = app.bundleIdentifier();
        const pid = app.processIdentifier();
        //Phoenix.log(`Checking if ${appName} (PID: ${pid}) is a user app`);

        // Bundle blacklist
        const bundleBlackList = [
            "com.apple.WebKit.GPU",
            "com.apple.ViewBridgeAuxiliary",
            "com.apple.universalaccessd",
            "com.apple.WindowManager",
            "com.apple.chronod",
            "com.apple.AuthenticationServices",
        ];
        
        // Exclude low-PID system processes
        if (pid < 1000) {
            Phoenix.log(`Skipping low-PID system process: ${appName} (PID: ${pid})`);
            return false;
        }

        // Check if the app path indicates a system app
        if ( !window.isNormal() ) {
            Phoenix.log(`Skipping window is not normal: ${appName}`);
            return false;
        }
        
        // Check if Application bundles are blacklisted
        if (bundleBlackList.includes(bundleId)) {
            Phoenix.log(`Skipping system app based on bundle ID: ${appName} (${bundleId})`);
            return false;
        }

        // Check if the window has a title
        const title = window.title();
        if (!title || title.trim() === "") {
            Phoenix.log(`Skipping window without a title: ${appName}`);
            return false;
        }

        // Check if the window has a visible frame
        const frame = window.frame();
        if (frame.width === 0 || frame.height === 0) {
            Phoenix.log(`Skipping window with zero-size frame: ${appName}`);
            return false;
        }

        // Check if process is not root
        const task = Task.run("/bin/bash", ["-c", `ps -o user= -p ${pid}`], (task) => {
            const user = task.output.trim();
            if (user === "root") {
                Phoenix.log(`Skipping process owned by root: ${appName} (PID: ${pid}, User: ${user})`);
                return false;
            }
        });

        if(!isProcessActive(pid)) {
            Phoenix.log(`Skipping dead process : ${appName} (PID: ${pid})`);
            return false;
        }

        if(isSystemPath(pid)) {
            Phoenix.log(`Skipping system path: ${appName} (PID: ${pid})`);
            return false;
        }

        // If all checks pass, assume it is a user-facing app
        Phoenix.log(`${appName} (PID: ${pid}) is a user app`);
        return true;
    } catch (error) {
        Phoenix.log(`Error filtering window: ${error}`);
        return false; // Safely skip on error
    }
}
