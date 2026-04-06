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

    private var scanTimer: Timer?

    // MARK: - Session Discovery

    /// Scan ~/.claude/sessions/ for all running Claude Code processes.
    /// Adds any sessions not already tracked (as idle).
    func scanForSessions() {
        let discovered = SessionScanner.scan()
        var added = 0

        let staleThreshold: TimeInterval = 2 * 3600 // 2 hours

        for disc in discovered {
            if sessions[disc.sessionId] == nil {
                let lastActivity = SessionScanner.lastActivityTime(
                    sessionId: disc.sessionId, cwd: disc.cwd
                ) ?? disc.startedAt

                // Skip stale sessions (no activity in 2+ hours)
                if Date().timeIntervalSince(lastActivity) > staleThreshold {
                    continue
                }

                // Priority: custom name > prompt label > folder name
                let customName = SessionScanner.customName(sessionId: disc.sessionId)
                let promptLabel = SessionScanner.promptLabel(sessionId: disc.sessionId)
                let folderName = (disc.cwd as NSString).lastPathComponent
                let label = customName
                    ?? ((promptLabel?.isEmpty == false) ? promptLabel! : folderName)

                // If transcript was modified recently, the session is probably
                // waiting for input (red). Otherwise it's idle (gray).
                let recentThreshold: TimeInterval = 300  // 5 minutes
                let isRecent = Date().timeIntervalSince(lastActivity) < recentThreshold
                let initialStatus: AgentStatus = isRecent ? .needsAttention : .idle

                sessions[disc.sessionId] = AgentSession(
                    id: disc.sessionId,
                    label: label,
                    cwd: disc.cwd,
                    status: initialStatus,
                    lastEventTime: lastActivity,
                    entrypoint: disc.entrypoint
                )
                added += 1
            }
        }

        // Remove sessions whose processes have died
        let aliveIds = Set(discovered.map { $0.sessionId })
        let deadIds = sessions.keys.filter { !aliveIds.contains($0) }
        for id in deadIds {
            sessions.removeValue(forKey: id)
            idleTimers[id]?.invalidate()
            idleTimers.removeValue(forKey: id)
        }

        // Also remove tracked sessions that have gone stale (idle 2+ hours, no hook activity)
        let staleIds = sessions.keys.filter { id in
            guard let session = sessions[id] else { return false }
            return (session.status == .idle || session.status == .done)
                && Date().timeIntervalSince(session.lastEventTime) > staleThreshold
        }
        for id in staleIds {
            sessions.removeValue(forKey: id)
            idleTimers[id]?.invalidate()
            idleTimers.removeValue(forKey: id)
        }

        // Deduplicate labels — append short ID when names collide
        deduplicateLabels()

        if added > 0 || !deadIds.isEmpty {
            Log.info("[Watchtower] Scan: found \(discovered.count) alive, added \(added), removed \(deadIds.count + staleIds.count) stale/dead")
            NotchWindowController.shared.refreshPanel()
        }
    }

    /// Start periodic scanning (every 10 seconds)
    func startPeriodicScan() {
        scanForSessions() // immediate first scan
        scanTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.scanForSessions()
        }
    }

    /// When multiple sessions have the same label, append #xxxx short ID
    private func deduplicateLabels() {
        // Group sessions by base label (without any existing #suffix)
        var labelGroups: [String: [String]] = [:]  // baseLabel -> [sessionIds]
        for (id, session) in sessions {
            let base = session.label.components(separatedBy: " #").first ?? session.label
            labelGroups[base, default: []].append(id)
        }

        for (_, ids) in labelGroups where ids.count > 1 {
            for id in ids {
                let base = sessions[id]?.label.components(separatedBy: " #").first ?? ""
                let shortId = String(id.prefix(4))
                sessions[id]?.label = "\(base) #\(shortId)"
            }
        }
    }

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
                // idle_prompt = Claude finished, waiting for next message.
                // That's green (done), not red. Red is only for permission blocks.
                if sessions[event.sessionId]?.status != .done {
                    sessions[event.sessionId]?.status = .done
                    sessions[event.sessionId]?.currentTool = nil
                    sessions[event.sessionId]?.currentToolSummary = nil
                }
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
            // Agent finished — green (done). Stays green for 3s before
            // idle_prompt can flip it to red. Gives that "build complete" moment.
            sessions[event.sessionId]?.status = .done
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
            let customName = SessionScanner.customName(sessionId: event.sessionId)
            let promptLabel = SessionScanner.promptLabel(sessionId: event.sessionId)
            let folderName = (event.cwd as NSString).lastPathComponent
            let label = customName
                ?? ((promptLabel?.isEmpty == false) ? promptLabel! : folderName)

            sessions[event.sessionId] = AgentSession(
                id: event.sessionId,
                label: label,
                cwd: event.cwd
            )
        }
    }

    /// After 5 minutes of no hook events, assume the agent finished.
    /// Long responses, subagent work, or complex generation can take
    /// several minutes between tool calls — 90s was way too aggressive.
    private func resetIdleTimer(for sessionId: String) {
        idleTimers[sessionId]?.invalidate()
        idleTimers[sessionId] = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.sessions[sessionId]?.status == .working {
                    // Was working, no events for 5 min → probably done
                    self.sessions[sessionId]?.status = .done
                    self.sessions[sessionId]?.currentTool = nil
                    self.sessions[sessionId]?.currentToolSummary = nil
                    NotchWindowController.shared.refreshPanel()
                }
            }
        }
    }
}
