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

    /// Extract a short label from the first user prompt in the transcript.
    /// Returns something like "fix the auth bug" or "add dark mode toggle"
    static func firstPromptLabel(sessionId: String) -> String? {
        guard let path = findTranscriptPath(sessionId: sessionId),
              let handle = FileHandle(forReadingAtPath: path) else {
            return nil
        }
        defer { handle.closeFile() }

        // Read first 50KB max (first prompt is always near the top)
        let data = handle.readData(ofLength: 50_000)
        guard let content = String(data: data, encoding: .utf8) else { return nil }

        for line in content.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  json["type"] as? String == "user",
                  let message = json["message"] as? [String: Any],
                  let messageContent = message["content"] else {
                continue
            }

            var text: String?

            // Content can be a string or array of content blocks
            if let str = messageContent as? String {
                text = str
            } else if let blocks = messageContent as? [[String: Any]] {
                // Find first text block (skip tool_result blocks)
                for block in blocks {
                    if block["type"] as? String == "text",
                       let t = block["text"] as? String {
                        text = t
                        break
                    }
                }
            }

            guard var prompt = text, !prompt.isEmpty else { continue }

            // Clean up: take first line, trim, lowercase
            prompt = prompt.components(separatedBy: "\n").first ?? prompt
            prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

            // Remove common prefixes
            let prefixes = ["can you ", "please ", "hey ", "hi ", "help me ", "i want to ", "i need to ", "let's ", "lets "]
            for prefix in prefixes {
                if prompt.lowercased().hasPrefix(prefix) {
                    prompt = String(prompt.dropFirst(prefix.count))
                    break
                }
            }

            // Truncate to ~40 chars at a word boundary
            if prompt.count > 40 {
                let truncated = String(prompt.prefix(40))
                if let lastSpace = truncated.lastIndex(of: " ") {
                    prompt = String(truncated[..<lastSpace])
                } else {
                    prompt = truncated
                }
                prompt += "..."
            }

            // Capitalize first letter
            if !prompt.isEmpty {
                prompt = prompt.prefix(1).uppercased() + prompt.dropFirst()
            }

            return prompt
        }

        return nil
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
