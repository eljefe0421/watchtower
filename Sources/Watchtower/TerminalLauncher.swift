import AppKit

/// Utility to jump to a terminal window at a specific working directory.
enum TerminalLauncher {
    /// Try to activate the terminal app that has a session at the given cwd.
    /// Falls back to opening a new terminal window at that path.
    static func jumpToSession(cwd: String) {
        // Try common terminal apps in preference order
        let terminalApps = [
            "com.mitchellh.ghostty",
            "net.kovidgoyal.kitty",
            "com.googlecode.iterm2",
            "com.apple.Terminal"
        ]

        for bundleId in terminalApps {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                app.activate()
                return
            }
        }

        // Fallback: open Terminal.app at the cwd
        let script = """
        tell application "Terminal"
            activate
            do script "cd \(cwd.replacingOccurrences(of: "\"", with: "\\\""))"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
