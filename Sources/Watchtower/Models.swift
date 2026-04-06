import Foundation

// MARK: - Agent Session

enum AgentStatus: String {
    case working        // yellow — actively using tools
    case done           // green — task complete
    case needsAttention // red — needs user input (permission or question)
}

struct PermissionRequest {
    let toolName: String
    let toolInput: String
    let timestamp: Date
}

struct AgentSession: Identifiable {
    let id: String                      // session_id from hooks
    var label: String                   // derived from cwd (folder name)
    var cwd: String
    var status: AgentStatus = .done
    var currentTool: String?
    var currentToolSummary: String?     // brief description of what tool is doing
    var lastEventTime: Date = Date()
    var pendingPermission: PermissionRequest?
    var entrypoint: String = "cli"      // "cli" or "claude-desktop"
}

// MARK: - Hook Event (parsed from incoming JSON)

struct HookEvent {
    let sessionId: String
    let hookEventName: String
    let cwd: String
    let toolName: String?
    let toolInput: [String: Any]?
    let message: String?
    let notificationType: String?
    let stopReason: String?

    init?(json: [String: Any]) {
        guard let sessionId = json["session_id"] as? String,
              let hookEventName = json["hook_event_name"] as? String else {
            return nil
        }
        self.sessionId = sessionId
        self.hookEventName = hookEventName
        self.cwd = json["cwd"] as? String ?? "unknown"
        self.toolName = json["tool_name"] as? String
        self.toolInput = json["tool_input"] as? [String: Any]
        self.message = json["message"] as? String
        self.notificationType = json["notification_type"] as? String
        self.stopReason = json["stop_reason"] as? String
    }

    /// One-line summary of what the tool is doing
    var toolSummary: String? {
        guard let name = toolName else { return nil }
        guard let input = toolInput else { return name }

        switch name {
        case "Bash":
            if let cmd = input["command"] as? String {
                let short = String(cmd.prefix(60))
                return short.count < cmd.count ? "\(short)..." : short
            }
        case "Read":
            if let path = input["file_path"] as? String {
                return (path as NSString).lastPathComponent
            }
        case "Write":
            if let path = input["file_path"] as? String {
                return (path as NSString).lastPathComponent
            }
        case "Edit":
            if let path = input["file_path"] as? String {
                return (path as NSString).lastPathComponent
            }
        case "Grep":
            if let pattern = input["pattern"] as? String {
                return "\"\(String(pattern.prefix(40)))\""
            }
        case "Glob":
            if let pattern = input["pattern"] as? String {
                return pattern
            }
        case "Agent":
            if let desc = input["description"] as? String {
                return desc
            }
        default:
            break
        }
        return name
    }
}
