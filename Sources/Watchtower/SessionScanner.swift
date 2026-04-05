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
        let projectsDir = NSHomeDirectory() + "/.claude/projects"
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: projectsDir) else {
            return nil
        }

        for dir in dirs {
            let transcriptPath = projectsDir + "/" + dir + "/" + sessionId + ".jsonl"
            if let attrs = try? FileManager.default.attributesOfItem(atPath: transcriptPath),
               let modDate = attrs[.modificationDate] as? Date {
                return modDate
            }
        }
        return nil
    }

    private static func isProcessAlive(pid: Int) -> Bool {
        kill(Int32(pid), 0) == 0
    }
}
