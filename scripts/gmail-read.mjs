#!/usr/bin/env node
// Gmail read helper — prints headers and decoded text body of a message.
// Auth: refresh token from ~/.gmail-mcp/credentials.json + ~/.gmail-mcp/gcp-oauth.keys.json.
//
// Usage:
//   node scripts/gmail-read.mjs --id <messageId>            Print From/Subject/Date + body text
//   node scripts/gmail-read.mjs --id <messageId> --links    Print only http(s) links found in body

import fs from 'fs';
import path from 'path';
import os from 'os';

const KEYS_PATH = path.join(os.homedir(), '.gmail-mcp', 'gcp-oauth.keys.json');
const TOKEN_PATH = path.join(os.homedir(), '.gmail-mcp', 'credentials.json');

function arg(name) {
  const i = process.argv.indexOf(name);
  return i !== -1 ? (process.argv[i + 1] ?? true) : undefined;
}
const idArg = arg('--id');
const linksOnly = process.argv.includes('--links');

if (!idArg) {
  console.error('Need --id <messageId>');
  process.exit(2);
}

const keys = JSON.parse(fs.readFileSync(KEYS_PATH, 'utf8')).installed;
const creds = JSON.parse(fs.readFileSync(TOKEN_PATH, 'utf8'));

async function accessToken() {
  const params = new URLSearchParams({
    client_id: keys.client_id,
    client_secret: keys.client_secret,
    refresh_token: creds.refresh_token,
    grant_type: 'refresh_token',
  });
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  });
  const j = await r.json();
  if (j.error) throw new Error('token refresh: ' + (j.error_description || j.error));
  return j.access_token;
}

function b64decode(data) {
  return Buffer.from(data.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
}

function collectParts(payload, out) {
  if (!payload) return;
  if (payload.body?.data && (payload.mimeType === 'text/plain' || payload.mimeType === 'text/html')) {
    out.push({ mime: payload.mimeType, text: b64decode(payload.body.data) });
  }
  for (const p of payload.parts || []) collectParts(p, out);
}

const token = await accessToken();
const r = await fetch(`https://gmail.googleapis.com/gmail/v1/users/me/messages/${idArg}?format=full`, {
  headers: { Authorization: 'Bearer ' + token },
});
if (!r.ok) throw new Error(`get message -> ${r.status} ${await r.text()}`);
const msg = await r.json();

const h = Object.fromEntries((msg.payload?.headers || []).map(x => [x.name, x.value]));
const parts = [];
collectParts(msg.payload, parts);
const plain = parts.find(p => p.mime === 'text/plain');
const html = parts.find(p => p.mime === 'text/html');
let body = plain ? plain.text : (html ? html.text.replace(/<style[\s\S]*?<\/style>/gi, '').replace(/<[^>]+>/g, ' ') : '(no text body)');

if (linksOnly) {
  const source = (plain ? plain.text : '') + ' ' + (html ? html.text : '');
  const links = [...new Set((source.match(/https?:\/\/[^\s"'<>\])]+/g) || []))];
  links.forEach(l => console.log(l));
} else {
  console.log(`From: ${h.From || ''}`);
  console.log(`Subject: ${h.Subject || ''}`);
  console.log(`Date: ${h.Date || ''}`);
  console.log('---');
  console.log(body.replace(/\r/g, '').replace(/\n{3,}/g, '\n\n').trim());
}
