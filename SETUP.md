# Watchtower — Setup on a New Device

macOS notch overlay that monitors all your parallel Claude Code agents with colored dots.

## Prerequisites
- macOS 14 Sonoma or later (MacBook with notch recommended)
- Xcode Command Line Tools: `xcode-select --install`
- Claude Code installed and working

## Install (30 seconds)

```bash
# Clone
git clone https://github.com/eljefe0421/watchtower.git ~/The\ Lab/Projects/watchtower

# Build and start
cd ~/The\ Lab/Projects/watchtower
make start
```

Done. Watchtower auto-installs hooks into `~/.claude/settings.json` on first launch.

## Verify it's working

```bash
# Check it's running
make status

# Check hooks are installed
grep 47777 ~/.claude/settings.json

# View logs
tail -f /tmp/watchtower.log
```

You should see colored dots appear in your MacBook notch area. Each dot = one Claude Code session.

## Daily commands

```bash
make start    # launch (background, survives terminal close)
make stop     # kill
make status   # check if running
```

Or use the `/watchtower` skill from any Claude Code session:
- "start watchtower"
- "stop watchtower"
- "show my agents"
- "name this Build Auth System" (renames the session in the notch)

## Install the /watchtower skill

If your skills sync via cerebro/iCloud, it's already there. Otherwise:

```bash
mkdir -p ~/.claude/skills/watchtower
cp -r ~/The\ Lab/Projects/watchtower/skills/watchtower/SKILL.md ~/.claude/skills/watchtower/
```

## What the dots mean
- 🟢 Green = agent is actively working (using tools)
- 🔴 Red (pulsing) = agent needs your attention (permission prompt)
- 🟠 Amber = error
- ⚫ Gray = idle (waiting for input)

Click the notch to expand and see session details, approve/deny permissions, or jump to terminal.

## Troubleshooting

**No dots showing:** Make sure Watchtower is running (`make status`). Sessions appear as they fire hooks — idle sessions show up within 10 seconds via the session scanner.

**Build fails:** Run `xcode-select --install` to ensure Command Line Tools are installed. If you get a SDK/compiler mismatch, run `softwareupdate --list` and install any available CLT update.

**Dots in wrong position:** Watchtower auto-detects the notch. On external monitors (no notch), dots appear as a floating pill at the top center.
