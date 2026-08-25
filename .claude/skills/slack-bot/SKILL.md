---
name: slack-bot
description: "Check for new Slack messages and send replies. Use when: the /loop cron fires and you need to check for incoming Slack messages, or when you need to send a reply back to the user on Slack."
---

# Slack Bot Skill

Send and receive messages via a personal Slack bot in a dedicated channel.

## Scripts

### Check for new messages
```bash
bash .claude/skills/slack-bot/check-slack.sh
```
Returns JSON of new messages from the allowed user (one JSON object per line). Returns nothing if there are no new messages.

### Send a reply
```bash
bash .claude/skills/slack-bot/send-slack.sh <channel_id> "<message>"
```
Sends a message to the specified channel. Supports Slack mrkdwn formatting.

## Environment Variables Required

- `SLACK_BOT_TOKEN` - Bot User OAuth Token (`xoxb-...`) from your Slack app
- `SLACK_CHANNEL_ID` - The channel where you talk to your agent (`C...`)
- `SLACK_ALLOWED_USER` - Your Slack user ID (`U...`); only messages from this user are processed
- Set all three in `.env` (the wrapper sources it on startup).

## Message JSON shape

Each incoming message is emitted as a compact JSON object:

- `chat_id` - the channel ID to reply into (pass it straight to `send-slack.sh`)
- `from` - the sender's Slack user ID
- `text` - the message text (or the file caption)
- `date` - Unix timestamp
- `image_path` - present when the user attached an image (downloaded to `/tmp`)
- `document_path` + `document_name` - present when the user attached a file

## How It Works

Messages reach you on one of two paths, and `check-slack.sh` picks the right one on its own.

**Normal path, the listener.** `scripts/slack-listener.sh` runs as a launchd daemon, watches Slack in plain shell (which costs no tokens), and wakes you only when a message actually arrives. It drops messages into `~/.claude-slack-inbox.jsonl`. In this mode `check-slack.sh` just drains that inbox and never touches the Slack API. This is why you are not woken up once a minute to look at an empty channel.

**Fallback path, direct polling.** If the listener is dead (its liveness beacon at `~/.agent-logs/slack-listener-alive` is older than 180 seconds), `check-slack.sh` polls Slack itself, exactly as it did before the listener existed. Comms survive a dead daemon, they just get slower and more expensive.

Either way:

1. The last seen message timestamp is tracked in `~/.claude-slack-ts`
2. On first run it bootstraps to "now", so it never floods on the channel's backlog
3. Only messages from the allowed user ID are returned (other users and bots are dropped)
4. `send-slack.sh` calls `chat.postMessage` with mrkdwn support

## When the listener is down

The hourly comms cron runs `bash scripts/slack-listener-status.sh`. If it reports `MORT`, tell the user on Slack that the listener is down, pass on the restart command from the status output, and keep working. Do not silently absorb it: while it is down, every message is delayed by up to an hour.

Full details in `docs/SLACK-LISTENER.md`.

## Notes

- The timestamp file prevents reprocessing old messages
- If no new messages exist, `check-slack.sh` returns empty output
- Attached files are downloaded to `/tmp` and surfaced via `image_path` / `document_path`
- The bot only sees messages in the one channel it was invited to (`SLACK_CHANNEL_ID`)
- Never run the listener and the Socket Mode bridge at the same time: both would wake you for the same message
