import AppKit
import SwiftUI

// MARK: - Notch Panel (NSPanel subclass)

/// A borderless, floating panel that sits over the notch area.
/// On Macs without a notch, it floats as a pill at the top center.
final class NotchPanel: NSPanel {
    private var hostingView: NSHostingView<AnyView>?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 50),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.hasShadow = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isFloatingPanel = true
        self.isOpaque = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.isMovableByWindowBackground = false
    }

    // Prevent macOS from constraining our window below the menu bar
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect  // don't constrain — we want to sit in the menu bar area
    }

    func setContent<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: AnyView(view))
        self.contentView = hosting
        self.hostingView = hosting
    }

    func positionForNotch(expanded: Bool) {
        guard let screen = notchScreen ?? NSScreen.main else {
            Log.info("[Watchtower] No screen found")
            return
        }

        let hasNotch = screen.safeAreaInsets.top > 0
        let notchHeight = screen.safeAreaInsets.top

        let compactHeight: CGFloat = hasNotch ? notchHeight : 38
        let expandedHeight: CGFloat = hasNotch ? notchHeight + 320 : 360
        let panelHeight = expanded ? expandedHeight : compactHeight

        let nw = notchWidth(for: screen) ?? 200
        let compactWidth: CGFloat = nw + 80
        let expandedWidth: CGFloat = max(380, nw + 120)
        let panelWidth = expanded ? expandedWidth : compactWidth

        let x = screen.frame.midX - panelWidth / 2
        let y = screen.frame.maxY - panelHeight

        let frame = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
        setFrame(frame, display: true, animate: expanded)
        Log.info("[Watchtower] Panel frame: \(frame), expanded: \(expanded)")
    }

    // MARK: - Notch Detection

    var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    func notchWidth(for screen: NSScreen) -> CGFloat? {
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else { return nil }
        return screen.frame.width - leftArea.width - rightArea.width
    }
}

// MARK: - Notch Window Controller

/// Manages the notch panel lifecycle and coordinates with the session manager.
final class NotchWindowController {
    static let shared = NotchWindowController()

    var isExpanded = false
    private var panel: NotchPanel?
    private var clickMonitor: Any?

    func setup() {
        Log.info("[Watchtower] Setting up notch panel...")
        let panel = NotchPanel()
        self.panel = panel

        let contentView = NotchContentView(controller: self)
        panel.setContent(contentView)

        panel.positionForNotch(expanded: false)
        panel.orderFrontRegardless()

        // Log actual frame to see if macOS constrains it
        Log.info("[Watchtower] Requested vs actual frame: \(panel.frame)")

        // Force reposition after display in case macOS adjusted it
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            panel.positionForNotch(expanded: false)
            Log.info("[Watchtower] After re-position: \(panel.frame)")
        }

        installClickOutsideMonitor()
    }

    func toggleExpanded() {
        isExpanded.toggle()
        refreshPanel()
    }

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        refreshPanel()
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        refreshPanel()
    }

    func refreshPanel() {
        let contentView = NotchContentView(controller: self)
        panel?.setContent(contentView)
        panel?.positionForNotch(expanded: isExpanded)
    }

    /// Collapse when clicking outside the panel
    private func installClickOutsideMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isExpanded else { return }
            if let panel = self.panel, !panel.frame.contains(NSEvent.mouseLocation) {
                self.collapse()
            }
        }
    }

    deinit {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
