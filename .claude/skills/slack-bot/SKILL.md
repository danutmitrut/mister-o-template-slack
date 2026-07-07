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

1. `check-slack.sh` calls the Slack Web API `conversations.history` endpoint for your channel
2. It tracks the last seen message timestamp in `~/.claude-slack-ts`
3. On first run it bootstraps to "now", so it never floods on the channel's backlog
4. Only messages from the allowed user ID are returned (other users and bots are dropped)
5. `send-slack.sh` calls `chat.postMessage` with mrkdwn support

## Notes

- The timestamp file prevents reprocessing old messages
- If no new messages exist, `check-slack.sh` returns empty output
- Attached files are downloaded to `/tmp` and surfaced via `image_path` / `document_path`
- The bot only sees messages in the one channel it was invited to (`SLACK_CHANNEL_ID`)
