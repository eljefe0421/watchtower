# Watchtower

macOS notch overlay for monitoring parallel Claude Code agent sessions.

## What it does
Turns the MacBook notch into a live dashboard showing colored dots for each active Claude Code session. Green = working, red pulsing = needs attention, gray = idle. Click to expand and see details, approve/deny permissions, or jump to the terminal.

## Tech stack
- **Language:** Swift (pure — zero external dependencies)
- **UI:** SwiftUI + AppKit (NSPanel for notch overlay)
- **Server:** Network framework (NWListener) for HTTP server on port 47777
- **Build:** `swiftc` via Makefile (SPM broken on current toolchain)
- **Min macOS:** 14 Sonoma

## How to build & run
```bash
make build    # compiles to .build/Watchtower
make run      # builds and launches
```

Note: SPM (`swift build`) doesn't work with the current Command Line Tools due to a PackageDescription API mismatch. Use `make` instead.

## How it works
1. Watchtower runs as a menu bar app (no dock icon)
2. Embedded HTTP server listens on port 47777
3. Claude Code hooks POST events (PreToolUse, Notification, Stop, etc.) to the server
4. Events update in-memory session state
5. Notch panel UI refreshes to show current agent statuses

## Hook configuration
On first launch, Watchtower auto-installs hooks in `~/.claude/settings.json`. To manually install: click "Install Hooks" in the menu bar dropdown.

## Key files
- `WatchtowerApp.swift` — app entry, menu bar, app delegate
- `EventServer.swift` — HTTP server (NWListener), held connections for approve/deny
- `SessionManager.swift` — agent session state management
- `NotchWindow.swift` — NSPanel subclass + window controller
- `Views.swift` — all SwiftUI views (compact dots, expanded list, agent rows)
- `Models.swift` — data models + hook event parsing
- `HookInstaller.swift` — patches ~/.claude/settings.json
- `Logger.swift` — file-based logging to /tmp/watchtower.log

## Common tasks
- **Debug:** `tail -f /tmp/watchtower.log`
- **Test events:** `curl -X POST http://localhost:47777/events -H 'Content-Type: application/json' -d '{"session_id":"test","hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"/tmp"}'`
- **Kill:** `pkill -f Watchtower`

## GitHub
https://github.com/eljefe0421/watchtower
