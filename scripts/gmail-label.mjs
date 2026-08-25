#!/usr/bin/env node
// Gmail label helper — creates a label if missing and applies it to messages matching a query.
// Auth: refresh token from ~/.gmail-mcp/credentials.json + ~/.gmail-mcp/gcp-oauth.keys.json (scope gmail.modify).
//
// Usage:
//   node scripts/gmail-label.mjs --label "Nume Eticheta" --query "<gmail query>"           DRY-RUN: list matches
//   node scripts/gmail-label.mjs --label "Nume Eticheta" --query "<gmail query>" --apply   Create label + apply to matches
//
// Safety: default DRY-RUN. Labeling is reversible (label can be removed / deleted).

import fs from 'fs';
import path from 'path';
import os from 'os';

const KEYS_PATH = path.join(os.homedir(), '.gmail-mcp', 'gcp-oauth.keys.json');
const TOKEN_PATH = path.join(os.homedir(), '.gmail-mcp', 'credentials.json');

function arg(name) {
  const i = process.argv.indexOf(name);
  return i !== -1 ? (process.argv[i + 1] ?? true) : undefined;
}
const labelName = arg('--label');
const queryArg = arg('--query');
const doApply = process.argv.includes('--apply');

if (!labelName || !queryArg) {
  console.error('Need --label "Name" and --query "<gmail query>"');
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

async function gapi(token, urlPath, method = 'GET', body = undefined) {
  const r = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/' + urlPath, {
    method,
    headers: {
      Authorization: 'Bearer ' + token,
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!r.ok) throw new Error(`${method} ${urlPath} -> ${r.status} ${await r.text()}`);
  return r.status === 204 ? {} : r.json();
}

const token = await accessToken();

async function ensureLabel(name) {
  const all = await gapi(token, 'labels');
  const found = (all.labels || []).find(l => l.name === name);
  if (found) return { id: found.id, created: false };
  const made = await gapi(token, 'labels', 'POST', {
    name,
    labelListVisibility: 'labelShow',
    messageListVisibility: 'show',
  });
  return { id: made.id, created: true };
}

const list = await gapi(token, `messages?q=${encodeURIComponent(queryArg)}&maxResults=100`);
const msgs = list.messages || [];
console.log(`Matches: ${msgs.length} for query: ${queryArg}`);
for (const m of msgs) {
  const full = await gapi(token, `messages/${m.id}?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date`);
  const h = Object.fromEntries((full.payload?.headers || []).map(x => [x.name, x.value]));
  console.log(`- ${m.id} | ${h.Date || ''} | ${h.From || ''} | ${h.Subject || ''}`);
}

if (!doApply) {
  console.log('\nDRY-RUN (no --apply). Label not created, nothing labeled.');
  process.exit(0);
}

const { id: labelId, created } = await ensureLabel(labelName);
console.log(`Label "${labelName}" ${created ? 'CREATED' : 'exists'} (id: ${labelId})`);

if (msgs.length > 0) {
  await gapi(token, 'messages/batchModify', 'POST', {
    ids: msgs.map(m => m.id),
    addLabelIds: [labelId],
  });
  console.log(`LABELED ${msgs.length} message(s) with "${labelName}"`);
} else {
  console.log('No messages to label.');
}
