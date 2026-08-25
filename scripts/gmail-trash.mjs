#!/usr/bin/env node
// Gmail trash helper — moves messages to Trash (reversible, auto-purged ~30d).
// Auth: refresh token from ~/.gmail-mcp/credentials.json + ~/.gmail-mcp/gcp-oauth.keys.json (scope gmail.modify).
//
// Usage:
//   node scripts/gmail-trash.mjs --id <messageId>            Trash one message by ID
//   node scripts/gmail-trash.mjs --query "<gmail query>"     DRY-RUN: list matches (default, no delete)
//   node scripts/gmail-trash.mjs --query "<gmail query>" --delete   Trash all matches
//
// Safety: --query defaults to DRY-RUN. Nothing is trashed without --delete or --id.
// Trash is reversible (not permanent delete) so false positives are recoverable.

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
const queryArg = arg('--query');
const doDelete = process.argv.includes('--delete');

if (!idArg && !queryArg) {
  console.error('Need --id <messageId> or --query "<gmail query>"');
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

async function gapi(token, urlPath, method = 'GET') {
  const r = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/' + urlPath, {
    method,
    headers: { Authorization: 'Bearer ' + token },
  });
  if (!r.ok) throw new Error(`${method} ${urlPath} -> ${r.status} ${await r.text()}`);
  return r.json();
}

const token = await accessToken();

async function trash(id) {
  await gapi(token, `messages/${id}/trash`, 'POST');
  console.log('TRASHED ' + id);
}

if (idArg) {
  await trash(idArg);
  process.exit(0);
}

// query mode
const list = await gapi(token, `messages?q=${encodeURIComponent(queryArg)}&maxResults=50`);
const msgs = list.messages || [];
console.log(`Matches: ${msgs.length} for query: ${queryArg}`);
for (const m of msgs) {
  const full = await gapi(token, `messages/${m.id}?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date`);
  const h = Object.fromEntries((full.payload?.headers || []).map(x => [x.name, x.value]));
  console.log(`- ${m.id} | ${h.Date || ''} | ${h.From || ''} | ${h.Subject || ''}`);
  if (doDelete) await trash(m.id);
}
if (!doDelete) console.log('\nDRY-RUN (no --delete). Nothing trashed.');
