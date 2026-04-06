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

Don't use a bash one-liner. Instead, do this in TWO steps:

**Step 1:** Find this session's ID by running:
```bash
python3 -c "
import json, os, glob
ppid = os.getppid()
# Walk up the process tree to find the claude process
pid = ppid
for _ in range(10):
    for f in glob.glob(os.path.expanduser('~/.claude/sessions/*.json')):
        d = json.load(open(f))
        if d['pid'] == pid:
            print(d['sessionId'])
            exit()
    # Get parent of current pid
    try:
        with open(f'/proc/{pid}/stat') as sf:
            pid = int(sf.read().split()[3])
    except:
        pid = int(os.popen(f'ps -o ppid= -p {pid}').read().strip() or '0')
# Fallback: most recently modified session file
import time
best = max(glob.glob(os.path.expanduser('~/.claude/sessions/*.json')), key=os.path.getmtime)
print(json.load(open(best))['sessionId'])
"
```

**Step 2:** Use the session ID from step 1 to rename:
```bash
curl -s -X POST http://localhost:47777/name \
  -H 'Content-Type: application/json' \
  -d '{"session_id": "PASTE_SESSION_ID", "name": "DESIRED_NAME"}'
```

Replace PASTE_SESSION_ID and DESIRED_NAME. Names persist in `~/.claude/watchtower/`.

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
