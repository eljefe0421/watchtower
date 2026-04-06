import SwiftUI

// MARK: - Top-Level Notch Content

struct NotchContentView: View {
    let controller: NotchWindowController

    var body: some View {
        let isExpanded = controller.isExpanded

        ZStack {
            // Background — black rounded rect extending below notch
            NotchBackgroundShape(cornerRadius: isExpanded ? 16 : 10)
                .fill(.black)

            // Content
            if isExpanded {
                ExpandedView()
            } else {
                CompactDotsView()
            }
        }
        .edgesIgnoringSafeArea(.all)
        .onTapGesture {
            controller.toggleExpanded()
        }
    }
}

// MARK: - Background Shape

struct NotchBackgroundShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cr = min(cornerRadius, rect.height / 2, rect.width / 2)

        // Top edge — flat (blends with notch/menu bar)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        // Right side down to bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cr))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cr, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + cr, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cr),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - Compact View (Colored Dots)

struct CompactDotsView: View {
    var body: some View {
        let sessions = SessionManager.shared.sortedSessions
        let notchH = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })?.safeAreaInsets.top ?? 0

        HStack(spacing: 8) {
            if sessions.isEmpty {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 8, height: 8)
            } else {
                ForEach(sessions) { session in
                    StatusDot(status: session.status)
                }
            }
        }
        .padding(.horizontal, 16)
        // Dots go at the BOTTOM of the panel (below the physical notch)
        // The top portion is just black that blends with the notch hardware
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 6)
    }
}

// MARK: - Animated Status Dot

struct StatusDot: View {
    let status: AgentStatus
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 12, height: 12)
            .shadow(color: dotColor.opacity(status == .needsAttention ? 0.9 : 0.6),
                    radius: status == .needsAttention ? 10 : 4)
            .scaleEffect(isPulsing && status == .needsAttention ? 1.5 : 1.0)
            .animation(
                status == .needsAttention
                    ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear { isPulsing = true }
            .onChange(of: status) { _, _ in
                isPulsing = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isPulsing = true
                }
            }
    }

    private var dotColor: Color {
        switch status {
        case .working: return Color(red: 1.0, green: 0.8, blue: 0.0)      // yellow — building
        case .done: return Color(red: 0.2, green: 0.9, blue: 0.3)         // green — task complete
        case .needsAttention: return Color(red: 1.0, green: 0.25, blue: 0.25) // red — needs input
        }
    }
}

// MARK: - Expanded View

struct ExpandedView: View {
    var body: some View {
        let manager = SessionManager.shared
        let server = WatchtowerApp.server

        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("WATCHTOWER")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                if !manager.sessions.isEmpty {
                    Button(action: { manager.removeAllSessions() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.3))
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, notchBottomPadding)
            .padding(.bottom, 8)

            Divider()
                .background(Color.white.opacity(0.15))

            if manager.sessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(manager.sortedSessions) { session in
                            AgentRowView(session: session, server: server)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No agents connected")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
            Text("Start Claude Code with hooks configured")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var notchBottomPadding: CGFloat {
        let notchScreen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        return (notchScreen?.safeAreaInsets.top ?? 8) + 4
    }
}

// MARK: - Agent Row

struct AgentRowView: View {
    let session: AgentSession
    let server: EventServer

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusDot(status: session.status)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(session.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)

                    // Show if CLI or Desktop
                    Text(session.entrypoint == "claude-desktop" ? "app" : "cli")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text(timeAgo(session.lastEventTime))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }

                if let permission = session.pendingPermission {
                    Text("Needs permission: \(permission.toolName)")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)

                    if !permission.toolInput.isEmpty {
                        Text(permission.toolInput)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        ActionButton(title: "Approve", color: .green) {
                            server.approvePermission(sessionId: session.id)
                            SessionManager.shared.clearPermission(for: session.id)
                            NotchWindowController.shared.refreshPanel()
                        }
                        ActionButton(title: "Deny", color: .red) {
                            server.denyPermission(sessionId: session.id)
                            SessionManager.shared.clearPermission(for: session.id)
                            NotchWindowController.shared.refreshPanel()
                        }
                        ActionButton(title: "Terminal", color: .blue) {
                            TerminalLauncher.jumpToSession(cwd: session.cwd)
                        }
                    }
                    .padding(.top, 4)

                } else if let tool = session.currentTool {
                    HStack(spacing: 4) {
                        Text(tool)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green.opacity(0.8))
                        if let summary = session.currentToolSummary, summary != tool {
                            Text(summary)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                    }
                } else if session.status == .done {
                    HStack(spacing: 8) {
                        Text("Done")
                            .font(.system(size: 11))
                            .foregroundStyle(.green.opacity(0.6))
                        ActionButton(title: "Terminal", color: .blue) {
                            TerminalLauncher.jumpToSession(cwd: session.cwd)
                        }
                    }
                } else if session.status == .done && session.currentTool == nil {
                    HStack(spacing: 8) {
                        Text("Done")
                            .font(.system(size: 11))
                            .foregroundStyle(.green.opacity(0.6))
                        ActionButton(title: "Terminal", color: .blue) {
                            TerminalLauncher.jumpToSession(cwd: session.cwd)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "now" }
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Menu Bar View (fallback / secondary access)

struct MenuBarView: View {
    var body: some View {
        let manager = SessionManager.shared

        VStack(alignment: .leading, spacing: 8) {
            Text("Watchtower")
                .font(.headline)

            if manager.sessions.isEmpty {
                Text("No agents connected")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(manager.sortedSessions) { session in
                    HStack {
                        Circle()
                            .fill(statusColor(session.status))
                            .frame(width: 8, height: 8)
                        Text(session.label)
                            .font(.system(size: 12))
                        Spacer()
                        Text(session.currentTool ?? "idle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Button("Install Hooks") {
                    HookInstaller.install()
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func statusColor(_ status: AgentStatus) -> Color {
        switch status {
        case .working: return .yellow
        case .done: return .green
        case .needsAttention: return .red
        }
    }
}
