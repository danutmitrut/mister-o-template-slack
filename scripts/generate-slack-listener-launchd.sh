#!/usr/bin/env bash
# Emits the Slack listener LaunchAgent plist. Parallels generate-supervisor-launchd.sh.
#
# KeepAlive is on: this daemon is meant to be running at all times, and if it
# dies the agent goes deaf until the hourly safety-net cron notices.
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OUT_FILE="${OUT_FILE:-${HOME}/Library/LaunchAgents/com.my-agent-slack.plist}"
LOG_DIR="${HOME}/.agent-logs"

mkdir -p "$(dirname "$OUT_FILE")" "$LOG_DIR"
cat > "$OUT_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.my-agent-slack</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${PROJECT_DIR}/scripts/slack-listener.sh</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>AGENT_DIR</key>
        <string>${PROJECT_DIR}</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/slack-listener.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/slack-listener.stderr.log</string>
    <key>WorkingDirectory</key>
    <string>${PROJECT_DIR}</string>
</dict>
</plist>
EOF
echo "wrote ${OUT_FILE}"
echo "Incarca-l cu: launchctl bootstrap gui/\$(id -u) ${OUT_FILE}"
