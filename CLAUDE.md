# Watchtower

macOS notch overlay for monitoring parallel Claude Code agent sessions.

## What it does
Turns the MacBook notch into a live dashboard showing colored dots for each active Claude Code session. Green = working, red pulsing = needs attention, gray = idle. Click to expand and see details, approve/deny permissions, rename sessions, or jump to terminal.

## Tech stack
- **Language:** Swift (pure — zero external dependencies)
- **UI:** SwiftUI + AppKit (NSPanel for notch overlay)
- **Server:** Network framework (NWListener) for HTTP server on port 47777
- **Build:** `swiftc` via Makefile
- **Min macOS:** 14 Sonoma
- **Requires:** Xcode Command Line Tools (`xcode-select --install`)

## Setup on a new device

```bash
# 1. Clone
git clone https://github.com/eljefe0421/watchtower.git ~/The\ Lab/Projects/watchtower

# 2. Build & start
cd ~/The\ Lab/Projects/watchtower
make start

# 3. Hooks auto-install on first run. Verify:
grep 47777 ~/.claude/settings.json

# 4. Copy the skill (if using shared skills via cerebro)
# The skill at cerebro/7 - claude/projects/watchtower/ syncs via iCloud
# Or manually: cp -r skills/watchtower ~/.claude/skills/watchtower
```

## Daily usage
```bash
make start    # launch in background (survives terminal close)
make stop     # kill it
make status   # check if running
```

## How it works
1. Runs as menu bar app (no dock icon)
2. Scans `~/.claude/sessions/*.json` every 10s to find ALL running sessions
3. HTTP server on port 47777 receives hook events for live status updates
4. Notch panel shows colored dots + expandable detail view
5. Session labels extracted from first user prompt, or custom name

## Naming sessions
Sessions auto-name from the first prompt. To set a custom name:
- Say "name this X" in any Claude Code session (via /watchtower skill)
- Or: `curl -X POST http://localhost:47777/name -H 'Content-Type: application/json' -d '{"session_id":"SESSION_ID","name":"My Label"}'`
- Names persist in `~/.claude/watchtower/{sessionId}.json`

## Key files
- `WatchtowerApp.swift` — app entry, menu bar, app delegate
- `EventServer.swift` — HTTP server, held connections for approve/deny, rename endpoint
- `SessionManager.swift` — session state + periodic scanning + dedup
- `SessionScanner.swift` — discovers sessions from disk, extracts prompt labels, custom names
- `NotchWindow.swift` — NSPanel subclass + window controller
- `Views.swift` — all SwiftUI views (compact dots, expanded list, agent rows)
- `Models.swift` — data models + hook event parsing
- `HookInstaller.swift` — patches ~/.claude/settings.json
- `Logger.swift` — file-based logging to /tmp/watchtower.log

## Common tasks
- **Debug:** `tail -f /tmp/watchtower.log`
- **Test event:** `curl -X POST http://localhost:47777/events -H 'Content-Type: application/json' -d '{"session_id":"test","hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"/tmp"}'`
- **Rename:** `curl -X POST http://localhost:47777/name -H 'Content-Type: application/json' -d '{"session_id":"ID","name":"Label"}'`

## GitHub
https://github.com/eljefe0421/watchtower
