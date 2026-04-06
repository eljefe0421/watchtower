import Foundation

/// Scans ~/.claude/sessions/ to discover all running Claude Code sessions,
/// even ones that haven't fired any hook events yet.
enum SessionScanner {

    struct DiscoveredSession {
        let pid: Int
        let sessionId: String
        let cwd: String
        let startedAt: Date
        let entrypoint: String  // "cli" or "claude-desktop"
    }

    /// Read all session files and return only those with alive processes
    static func scan() -> [DiscoveredSession] {
        let sessionsDir = NSHomeDirectory() + "/.claude/sessions"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: sessionsDir) else {
            return []
        }

        var results: [DiscoveredSession] = []

        for file in files where file.hasSuffix(".json") {
            let path = sessionsDir + "/" + file
            guard let data = FileManager.default.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = json["pid"] as? Int,
                  let sessionId = json["sessionId"] as? String,
                  let cwd = json["cwd"] as? String else {
                continue
            }

            // Check if process is alive
            guard isProcessAlive(pid: pid) else { continue }

            let startedAt: Date
            if let ms = json["startedAt"] as? Double {
                startedAt = Date(timeIntervalSince1970: ms / 1000.0)
            } else {
                startedAt = Date()
            }

            let entrypoint = json["entrypoint"] as? String ?? "unknown"

            results.append(DiscoveredSession(
                pid: pid,
                sessionId: sessionId,
                cwd: cwd,
                startedAt: startedAt,
                entrypoint: entrypoint
            ))
        }

        return results
    }

    /// Check activity by looking at the transcript file's modification time
    static func lastActivityTime(sessionId: String, cwd: String) -> Date? {
        guard let path = findTranscriptPath(sessionId: sessionId) else { return nil }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let modDate = attrs[.modificationDate] as? Date {
            return modDate
        }
        return nil
    }

    /// Extract a label from the first substantive user prompt in the transcript.
    /// Skips very short prompts (< 15 chars) to find one that describes the task.
    static func promptLabel(sessionId: String) -> String? {
        guard let path = findTranscriptPath(sessionId: sessionId),
              let handle = FileHandle(forReadingAtPath: path) else {
            return nil
        }
        defer { handle.closeFile() }

        // Read first 80KB — the substantive first prompt is near the top
        let data = handle.readData(ofLength: 80_000)
        guard let content = String(data: data, encoding: .utf8) else { return nil }

        for line in content.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  json["type"] as? String == "user",
                  let message = json["message"] as? [String: Any],
                  let messageContent = message["content"] else {
                continue
            }

            // Only string content = real user prompt (arrays are tool results)
            guard let str = messageContent as? String, str.count >= 15 else { continue }

            let cleaned = cleanPrompt(str)
            if cleaned.count >= 5 {
                return cleaned
            }
        }

        return nil
    }

    /// Clean a raw prompt into a short, distinctive label
    private static func cleanPrompt(_ raw: String) -> String {
        var text = raw

        // Take first line only
        text = text.components(separatedBy: "\n").first ?? text
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip leading special chars (❯, >, -, etc)
        while let first = text.first, !first.isLetter && !first.isNumber {
            text = String(text.dropFirst())
        }
        text = text.trimmingCharacters(in: .whitespaces)

        // Strip filler prefixes (case insensitive)
        // If it's a URL, label it as such
        if text.lowercased().hasPrefix("http") {
            return "Shared link"
        }

        let prefixes = [
            "can you ", "could you ", "please ", "hey ", "hi ", "ok ", "okay ",
            "help me ", "i want to ", "i need to ", "i'd like to ",
            "let's ", "lets ", "let me ", "now ", "also ", "and ",
            "go ahead and ", "try to ", "we need to ", "we should ",
            "im trying to ", "i'm trying to ", "figure out how to ",
            "so ", "well ", "alright ", "right ", "btw ",
            "im about to ", "i'm about to ", "i am going to ",
            "pull up ", "look at ", "check out ", "show me ",
            "do ", "run ", "our ", "the ", "my ", "a ",
        ]
        var stripped = true
        while stripped {
            stripped = false
            for prefix in prefixes {
                if text.lowercased().hasPrefix(prefix) {
                    text = String(text.dropFirst(prefix.count))
                    stripped = true
                    break
                }
            }
        }

        // Truncate to 25 chars at word boundary
        if text.count > 25 {
            let truncated = String(text.prefix(25))
            if let lastSpace = truncated.lastIndex(of: " ") {
                text = String(truncated[..<lastSpace])
            } else {
                text = truncated
            }
        }

        // Capitalize first letter
        text = text.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            text = text.prefix(1).uppercased() + text.dropFirst()
        }

        return text.isEmpty ? nil ?? "" : text
    }

    // MARK: - Custom Names

    private static let metadataDir = NSHomeDirectory() + "/.claude/watchtower"

    /// Read a custom name set by the user for this session
    static func customName(sessionId: String) -> String? {
        let path = metadataDir + "/" + sessionId + ".json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String, !name.isEmpty else {
            return nil
        }
        return name
    }

    /// Set a custom name for a session (called from hook or CLI)
    static func setCustomName(sessionId: String, name: String) {
        let dirPath = metadataDir
        try? FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)

        let path = dirPath + "/" + sessionId + ".json"
        let json: [String: Any] = ["name": name, "updatedAt": ISO8601DateFormatter().string(from: Date())]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Private

    private static func findTranscriptPath(sessionId: String) -> String? {
        let projectsDir = NSHomeDirectory() + "/.claude/projects"
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: projectsDir) else {
            return nil
        }

        for dir in dirs {
            let path = projectsDir + "/" + dir + "/" + sessionId + ".jsonl"
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func isProcessAlive(pid: Int) -> Bool {
        kill(Int32(pid), 0) == 0
    }
}
