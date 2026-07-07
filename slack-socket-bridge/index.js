#!/usr/bin/env node
// Slack Socket Mode bridge for the personal agent.
// Real-time alternative to the 1-minute polling in .claude/skills/slack-bot.
//
//   Inbound  (Slack -> agent): a Slack message arrives over the Socket Mode
//            WebSocket and is injected into the live tmux session with
//            `tmux send-keys`, waking the agent instantly.
//   Outbound (agent -> Slack): unchanged. The agent replies with
//            .claude/skills/slack-bot/send-slack.sh, exactly as in polling mode.
//
// Adapted from the Nova cortextOS bridge pattern (Bolt Socket Mode + media
// download), with cortextOS bus routing replaced by tmux injection, since this
// template is a single Claude session, not a multi-agent bus.
const { App } = require('@slack/bolt');
const { execFileSync } = require('child_process');
const { existsSync, readFileSync, writeFileSync } = require('fs');
const { join } = require('path');

function loadDotEnv(filePath) {
  if (!existsSync(filePath)) return;
  for (const line of readFileSync(filePath, 'utf-8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    if (!process.env[key]) process.env[key] = value;
  }
}

// Read the agent's root .env (SLACK_BOT_TOKEN / SLACK_CHANNEL_ID / SLACK_ALLOWED_USER),
// then an optional local .env here that can override or add SLACK_APP_TOKEN.
const AGENT_DIR = process.env.AGENT_DIR || join(__dirname, '..');
loadDotEnv(join(AGENT_DIR, '.env'));
loadDotEnv(join(__dirname, '.env'));

const required = ['SLACK_BOT_TOKEN', 'SLACK_APP_TOKEN', 'SLACK_CHANNEL_ID'];
for (const key of required) {
  if (!process.env[key]) {
    console.error(`[slack-bridge] Missing required env var: ${key}`);
    process.exit(1);
  }
}

const channelId = process.env.SLACK_CHANNEL_ID;
const allowedUser = process.env.SLACK_ALLOWED_USER || '';
const tmuxSession = process.env.TMUX_SESSION || 'my-agent';
const mediaDir = '/tmp';
const maxFileBytes = Number(process.env.SLACK_MAX_FILE_BYTES || 50 * 1024 * 1024);

function cleanSlackText(text) {
  return String(text || '')
    .replace(/<@[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .trim();
}

function sanitizeFilename(value) {
  return String(value || 'slack-file')
    .replace(/[/\\?%*:|"<>]/g, '-')
    .replace(/\s+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 120) || 'slack-file';
}

async function downloadFiles(files = []) {
  const out = [];
  for (const file of files) {
    const size = Number(file.size || 0);
    const name = file.name || file.title || `${file.id || 'file'}.${file.filetype || 'bin'}`;
    const local = join(mediaDir, `slack-${Date.now()}-${sanitizeFilename(name)}`);
    if (size > maxFileBytes) { out.push({ name, skipped: `larger than ${maxFileBytes} bytes` }); continue; }
    const url = file.url_private_download || file.url_private;
    if (!url) { out.push({ name, skipped: 'no private url' }); continue; }
    try {
      const res = await fetch(url, { headers: { Authorization: `Bearer ${process.env.SLACK_BOT_TOKEN}` } });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      writeFileSync(local, Buffer.from(await res.arrayBuffer()));
      out.push({ name, local });
    } catch (err) {
      out.push({ name, error: err.message });
    }
  }
  return out;
}

function hasSession() {
  try { execFileSync('tmux', ['has-session', '-t', tmuxSession], { stdio: 'ignore' }); return true; }
  catch { return false; }
}

// Serialize injections so two quick messages can't interleave in the REPL.
let queue = Promise.resolve();
function sendToAgent(promptLine) {
  queue = queue.then(() => {
    if (!hasSession()) {
      console.error(`[slack-bridge] tmux session '${tmuxSession}' not found; dropping message. Is the agent running?`);
      return;
    }
    try {
      // -l sends the text literally; a separate Enter submits it. The prompt is a
      // single line, so no embedded newline can submit half a message early.
      execFileSync('tmux', ['send-keys', '-t', tmuxSession, '-l', promptLine]);
      execFileSync('tmux', ['send-keys', '-t', tmuxSession, 'Enter']);
    } catch (err) {
      console.error(`[slack-bridge] send-keys failed: ${err.message}`);
    }
  });
  return queue;
}

async function forward({ text, files, channel, user }) {
  const cleaned = cleanSlackText(text);
  const downloaded = await downloadFiles(files || []);
  if (!cleaned && downloaded.length === 0) return;

  const parts = [`[SLACK from ${user || 'user'}] ${cleaned || '(no text)'}`];
  for (const f of downloaded) {
    if (f.local) parts.push(`attached file "${f.name}" saved at ${f.local} (use the Read tool on it)`);
    else parts.push(`attached file "${f.name}" not downloaded (${f.skipped || f.error})`);
  }
  parts.push(`Reply with: bash .claude/skills/slack-bot/send-slack.sh ${channel} "<your reply>"`);
  // Collapse to one line so the REPL receives a single prompt.
  const line = parts.join(' | ').replace(/\s*\n\s*/g, ' ');
  await sendToAgent(line);
  console.log(`[slack-bridge] forwarded message from ${user} to session '${tmuxSession}'`);
}

const app = new App({
  token: process.env.SLACK_BOT_TOKEN,
  appToken: process.env.SLACK_APP_TOKEN,
  socketMode: true,
});

app.event('app_mention', async ({ event }) => {
  if (allowedUser && event.user !== allowedUser) return;
  if (event.channel !== channelId) return;
  try { await forward({ text: event.text, files: event.files || [], channel: event.channel, user: event.user }); }
  catch (err) { console.error(`[slack-bridge] app_mention failed: ${err.message}`); }
});

app.message(async ({ message }) => {
  if (message.bot_id) return;                                   // never echo the bot's own replies
  if (message.subtype && message.subtype !== 'file_share') return;
  if (allowedUser && message.user !== allowedUser) return;      // only the owner
  if (message.channel !== channelId) return;                    // only the dedicated channel
  try { await forward({ text: message.text, files: message.files || [], channel: message.channel, user: message.user }); }
  catch (err) { console.error(`[slack-bridge] message failed: ${err.message}`); }
});

(async () => {
  await app.start();
  console.log(`[slack-bridge] running (Socket Mode). Slack channel ${channelId} -> tmux session '${tmuxSession}'. Replies via send-slack.sh.`);
})();
