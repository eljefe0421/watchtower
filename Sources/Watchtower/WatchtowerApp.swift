import SwiftUI
import AppKit

/// Global server instance — shared between views and app
@MainActor
enum WatchtowerApp {
    static let server = EventServer()
}

/// App delegate handles early setup before SwiftUI views appear
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No dock icon
        NSApplication.shared.setActivationPolicy(.accessory)

        // Start HTTP server
        let server = WatchtowerApp.server
        server.onEvent = { event in
            DispatchQueue.main.async {
                SessionManager.shared.processEvent(event)
            }
        }
        server.start()

        // Install hooks if not already done
        if !HookInstaller.isInstalled {
            Log.info("[Watchtower] Hooks not detected — installing...")
            HookInstaller.install()
        }

        // Set up notch overlay after a brief delay to let the window server settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotchWindowController.shared.setup()
        }
    }
}

@main
struct WatchtowerAppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var manager = SessionManager.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "eye.fill")
                if manager.attentionCount > 0 {
                    Text("\(manager.attentionCount)")
                        .font(.system(size: 9, weight: .bold))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
