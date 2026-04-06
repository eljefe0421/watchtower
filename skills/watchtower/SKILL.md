---
name: watchtower
description: "Control the Watchtower notch monitor for Claude Code agents. Use this skill when the user says: 'watchtower', 'start watchtower', 'stop watchtower', 'watchtower status', 'kill watchtower', 'agents', 'show my agents', 'what agents are running', 'notch', 'rebuild watchtower', 'name this', 'rename this session', 'call this session', 'hide notch', 'show notch', 'toggle notch'."
---

# Watchtower Control

Manage the Watchtower macOS notch overlay that monitors parallel Claude Code agent sessions.

## Commands

| Request | What to do |
|---------|-----------|
| `watchtower` / `watchtower status` / `agents` | Check if Watchtower is running, show status |
| `start watchtower` | Build and launch Watchtower in background |
| `stop watchtower` / `kill watchtower` | Stop the background process |
| `restart watchtower` | Stop then start |
| `rebuild watchtower` | Full rebuild + restart |
| `show my agents` / `what agents are running` | List all detected Claude Code sessions |
| `watchtower logs` | Show recent log entries |
| `name this X` / `rename this session X` / `call this X` | Rename the current session in Watchtower |
| `hide notch` / `show notch` / `toggle notch` | Show or hide the notch overlay |

## Implementation

### Status check
```bash
cd ~/The\ Lab/Projects/watchtower && make status
```

### Start
```bash
cd ~/The\ Lab/Projects/watchtower && make start
```

### Stop
```bash
cd ~/The\ Lab/Projects/watchtower && make stop
```

### Rebuild + restart
```bash
cd ~/The\ Lab/Projects/watchtower && make start
```
(Makefile automatically rebuilds if sources changed)

### Rename current session

To rename THIS session in Watchtower, POST to the /name endpoint.
The session_id comes from the CLAUDE_SESSION_ID environment variable,
or you can find it from the transcript path.

```bash
# Get the current session ID
SESSION_ID=$(ls -t ~/.claude/sessions/*.json | head -1 | xargs python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['sessionId'])")

# Rename it
curl -s -X POST http://localhost:47777/name \
  -H 'Content-Type: application/json' \
  -d "{\"session_id\": \"$SESSION_ID\", \"name\": \"THE_NAME_HERE\"}"
```

Replace THE_NAME_HERE with the user's desired name. Keep it short (under 25 chars).
The name persists across Watchtower restarts in `~/.claude/watchtower/{sessionId}.json`.

### Toggle notch visibility (hide/show)
```bash
curl -s -X POST http://localhost:47777/toggle
```

### Show all agents
```bash
for f in ~/.claude/sessions/*.json; do
  pid=$(python3 -c "import json; d=json.load(open('$f')); print(d['pid'])")
  if kill -0 "$pid" 2>/dev/null; then
    python3 -c "
import json
d = json.load(open('$f'))
ep = 'desktop' if d.get('entrypoint') == 'claude-desktop' else 'cli'
cwd = d['cwd'].replace('/Users/d/', '~/')
print(f\"  PID {d['pid']:>6} | {ep:>7} | {cwd}\")
"
  fi
done
```

### Show logs
```bash
tail -20 /tmp/watchtower.log
```

## Setup on a New Device

1. Clone: `git clone https://github.com/eljefe0421/watchtower.git ~/The\ Lab/Projects/watchtower`
2. Build: `cd ~/The\ Lab/Projects/watchtower && make build`
3. Start: `make start`
4. Hooks auto-install on first run. Verify: `cat ~/.claude/settings.json | grep 47777`
5. Copy skill: symlink or copy this skill folder to `~/.claude/skills/watchtower/`

## Notes
- Watchtower runs as a background process — use `make start` not `make run`
- It auto-discovers ALL Claude Code sessions (cli + desktop) on startup
- Sessions appear as colored dots in the MacBook notch area
- Custom names persist in `~/.claude/watchtower/{sessionId}.json`
- The app auto-installs hooks in `~/.claude/settings.json` on first run
- Project location: `~/The Lab/Projects/watchtower`
- GitHub: https://github.com/eljefe0421/watchtower
