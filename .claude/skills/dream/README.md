# Dream - Memory Consolidation for Claude Code

Your AI agent dreams like you do. Consolidates memory while you sleep.

Anthropic is building an auto-dream feature into Claude Code (currently unreleased). This skill replicates that functionality today - no feature flags, no waiting for rollout. Drop it in and your agent's memory stays clean, current, and contradiction-free.

## What It Does

When you use Claude Code across many sessions, auto-memory accumulates noise: stale facts, contradictions, relative dates that lose meaning. Dream fixes this by running a 4-phase consolidation pass over your memory files - the same way your brain consolidates memories during sleep.

**Phase 1 - Orient:** Reads your current memory directory to understand what exists.

**Phase 2 - Gather Signal:** Scans recent session transcripts (JSONL files) for user corrections, preference changes, important decisions, and recurring patterns. Uses targeted grep, not full reads.

**Phase 3 - Consolidate:** Merges new findings into existing memory. Converts relative dates to absolute. Resolves contradictions. Removes references to nonexistent files. No duplicates.

**Phase 4 - Prune & Index:** Rebuilds MEMORY.md as a lean index under 200 lines. Removes stale pointers. Demotes verbose entries to topic files.

## Auto-Trigger

Includes a native Claude Code Stop hook that checks every time you exit a session:
- Has 24+ hours passed since the last dream?
- If yes, flags the next session to run `/dream` automatically.

Zero overhead when conditions aren't met (~10ms check on exit).

## Memory System Auto-Detection

On first install, the skill detects which memory system you're using:
- **Native Claude Code** (`~/.claude/projects/*/memory/`) - default
- **OpenClaw-style** (`./memory/` with daily logs)
- **Project-root** (`./MEMORY.md` in project root)

If nothing is detected, defaults to native Claude Code memory.

## Quick Start

### Option 1: Clone into skills directory

```bash
git clone https://github.com/grandamenium/dream-skill.git ~/.claude/skills/dream
```

### Option 2: Run the installer

```bash
git clone https://github.com/grandamenium/dream-skill.git /tmp/dream-skill
bash /tmp/dream-skill/install.sh --auto
```

### Option 3: Manual install

1. Copy `SKILL.md` and `should-dream.sh` to `~/.claude/skills/dream/`
2. Run `chmod +x ~/.claude/skills/dream/should-dream.sh`
3. Start a Claude Code session and say `/dream` to run it

## What's Included

| File | Purpose |
|------|---------|
| `SKILL.md` | The skill prompt - 4-phase consolidation instructions with onboarding |
| `should-dream.sh` | Condition checker (24hr timer) |
| `dream-hook.sh` | Stop hook that flags next session for dreaming |
| `install.sh` | One-command installer with `--auto` flag for hook setup |
| `test-dream.sh` | Creates test fixtures and verifies consolidation results |

## Usage

### Manual
```
/dream
```

### Automatic (after install --auto)
Just use Claude Code normally. The Stop hook checks on every session exit. When 24 hours have passed, your next session automatically runs a dream consolidation in the background.

## Requirements

- Claude Code v2.1.59+ (auto-memory support)
- No additional dependencies

## How It Compares to Anthropic's Auto-Dream

| Feature | Anthropic (unreleased) | This Skill |
|---------|----------------------|------------|
| 4-phase consolidation | Yes | Yes |
| Session transcript scanning | Yes | Yes |
| Contradiction resolution | Yes | Yes |
| Date normalization | Yes | Yes |
| Auto-trigger | Built into binary | Stop hook + flag file |
| Memory system detection | Native only | Native + OpenClaw + custom |
| Available now | Behind feature flag | Yes |

## License

MIT
