#!/usr/bin/env bash
# Emits the supervisor LaunchAgent plist. Parallels generate-launchd.sh.
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${CONFIG_FILE:-${PROJECT_DIR}/config.json}"
OUT_FILE="${OUT_FILE:-${HOME}/Library/LaunchAgents/com.my-agent-supervisor.plist}"
LOG_DIR="${HOME}/.agent-logs"

tick="$(jq -r '.supervisor.tick_seconds // 240' "$CONFIG_FILE" 2>/dev/null || echo 240)"
# Guard: a non-integer tick (e.g. a string in config) would emit an invalid plist.
[[ "$tick" =~ ^[0-9]+$ ]] || tick=240

mkdir -p "$(dirname "$OUT_FILE")" "$LOG_DIR"
cat > "$OUT_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.my-agent-supervisor</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${PROJECT_DIR}/scripts/supervisor.sh</string>
        <string>${PROJECT_DIR}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>${tick}</integer>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/supervisor.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/supervisor.stderr.log</string>
    <key>WorkingDirectory</key>
    <string>${PROJECT_DIR}</string>
</dict>
</plist>
EOF
echo "wrote ${OUT_FILE} (StartInterval=${tick})"
