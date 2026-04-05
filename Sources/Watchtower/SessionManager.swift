import Foundation
import SwiftUI

@Observable
final class SessionManager {
    static let shared = SessionManager()

    var sessions: [String: AgentSession] = [:]
    private var idleTimers: [String: Timer] = [:]

    /// Sorted sessions for display (needs-attention first, then working, then idle)
    var sortedSessions: [AgentSession] {
        sessions.values.sorted { a, b in
            if a.status == .needsAttention && b.status != .needsAttention { return true }
            if a.status != .needsAttention && b.status == .needsAttention { return false }
            if a.status == .working && b.status != .working { return true }
            if a.status != .working && b.status == .working { return false }
            return a.lastEventTime > b.lastEventTime
        }
    }

    /// Number of agents that need attention right now
    var attentionCount: Int {
        sessions.values.filter { $0.status == .needsAttention }.count
    }

    /// True if any agent needs attention
    var hasAttention: Bool { attentionCount > 0 }

    // MARK: - Event Processing

    func processEvent(_ event: HookEvent) {
        Log.info("[Watchtower] Event: \(event.hookEventName) from \(event.sessionId.prefix(8)) tool=\(event.toolName ?? "nil")")
        ensureSession(for: event)
        resetIdleTimer(for: event.sessionId)

        switch event.hookEventName {
        case "PreToolUse":
            sessions[event.sessionId]?.status = .working
            sessions[event.sessionId]?.currentTool = event.toolName
            sessions[event.sessionId]?.currentToolSummary = event.toolSummary
            sessions[event.sessionId]?.pendingPermission = nil
            sessions[event.sessionId]?.lastEventTime = Date()

        case "PostToolUse":
            sessions[event.sessionId]?.status = .working
            sessions[event.sessionId]?.lastEventTime = Date()

        case "Notification":
            if event.notificationType == "permission_prompt" || event.message?.contains("permission") == true {
                sessions[event.sessionId]?.status = .needsAttention
                if let toolName = event.toolName {
                    sessions[event.sessionId]?.pendingPermission = PermissionRequest(
                        toolName: toolName,
                        toolInput: event.toolSummary ?? "",
                        timestamp: Date()
                    )
                }
            } else if event.notificationType == "idle_prompt" {
                sessions[event.sessionId]?.status = .idle
                sessions[event.sessionId]?.currentTool = nil
                sessions[event.sessionId]?.currentToolSummary = nil
            }
            sessions[event.sessionId]?.lastEventTime = Date()

        case "PermissionRequest":
            sessions[event.sessionId]?.status = .needsAttention
            sessions[event.sessionId]?.pendingPermission = PermissionRequest(
                toolName: event.toolName ?? "Unknown",
                toolInput: event.toolSummary ?? "",
                timestamp: Date()
            )
            sessions[event.sessionId]?.lastEventTime = Date()

        case "Stop":
            sessions[event.sessionId]?.status = .idle
            sessions[event.sessionId]?.currentTool = nil
            sessions[event.sessionId]?.currentToolSummary = nil
            sessions[event.sessionId]?.pendingPermission = nil
            sessions[event.sessionId]?.lastEventTime = Date()

        case "SubagentStart":
            sessions[event.sessionId]?.status = .working
            sessions[event.sessionId]?.lastEventTime = Date()

        case "SubagentStop":
            sessions[event.sessionId]?.lastEventTime = Date()

        default:
            sessions[event.sessionId]?.lastEventTime = Date()
        }

        // Refresh the notch panel to reflect new state
        NotchWindowController.shared.refreshPanel()
        Log.info("[Watchtower] Sessions: \(sessions.count), attention: \(attentionCount)")
    }

    func clearPermission(for sessionId: String) {
        sessions[sessionId]?.pendingPermission = nil
        sessions[sessionId]?.status = .working
    }

    func removeSession(_ sessionId: String) {
        sessions.removeValue(forKey: sessionId)
        idleTimers[sessionId]?.invalidate()
        idleTimers.removeValue(forKey: sessionId)
    }

    func removeAllSessions() {
        sessions.removeAll()
        idleTimers.values.forEach { $0.invalidate() }
        idleTimers.removeAll()
    }

    // MARK: - Private

    private func ensureSession(for event: HookEvent) {
        if sessions[event.sessionId] == nil {
            let label = (event.cwd as NSString).lastPathComponent
            sessions[event.sessionId] = AgentSession(
                id: event.sessionId,
                label: label,
                cwd: event.cwd
            )
        }
    }

    /// After 90 seconds of no events, mark the session idle
    private func resetIdleTimer(for sessionId: String) {
        idleTimers[sessionId]?.invalidate()
        idleTimers[sessionId] = Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.sessions[sessionId]?.status == .working {
                    self.sessions[sessionId]?.status = .idle
                    self.sessions[sessionId]?.currentTool = nil
                    self.sessions[sessionId]?.currentToolSummary = nil
                }
            }
        }
    }
}
