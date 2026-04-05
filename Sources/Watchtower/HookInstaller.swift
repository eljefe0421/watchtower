import Foundation

/// Patches ~/.claude/settings.json with the Watchtower hook configuration.
enum HookInstaller {
    static let port: UInt16 = 47777

    static func install() {
        let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
        let settingsURL = URL(fileURLWithPath: settingsPath)

        // Read existing settings or start fresh
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        // Build hook config
        let url = "http://localhost:\(port)/events"

        func hookEntry(timeout: Int = 3) -> [[String: Any]] {
            [["matcher": "", "hooks": [["type": "http", "url": url, "timeout": timeout]]]]
        }

        let hooks: [String: Any] = [
            "PreToolUse": hookEntry(),
            "PostToolUse": hookEntry(),
            "Notification": hookEntry(),
            "Stop": hookEntry(),
            "SubagentStart": hookEntry(),
            "SubagentStop": hookEntry(),
            "PermissionRequest": hookEntry(timeout: 30),  // held for approve/deny
        ]

        settings["hooks"] = hooks

        // Write back
        do {
            // Ensure .claude directory exists
            let claudeDir = NSHomeDirectory() + "/.claude"
            try FileManager.default.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)

            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsURL, options: .atomic)
            Log.info("[Watchtower] Hooks installed in \(settingsPath)")
        } catch {
            Log.info("[Watchtower] Failed to install hooks: \(error)")
        }
    }

    /// Check if hooks are already configured
    static var isInstalled: Bool {
        let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        // Check if at least one hook points to our port
        for (_, value) in hooks {
            if let arr = value as? [[String: Any]] {
                for entry in arr {
                    if let hooksList = entry["hooks"] as? [[String: Any]] {
                        for hook in hooksList {
                            if let hookURL = hook["url"] as? String, hookURL.contains("\(port)") {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }
}
