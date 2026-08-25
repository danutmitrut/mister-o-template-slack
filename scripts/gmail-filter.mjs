#!/usr/bin/env node
// Gmail native filter helper — creates a native Gmail filter that auto-labels matching incoming mail.
// Auth: refresh token from ~/.gmail-mcp/credentials.json + ~/.gmail-mcp/gcp-oauth.keys.json
//       (needs scope gmail.settings.basic — extend gmail-auth.mjs and re-auth if missing).
//
// Usage:
//   node scripts/gmail-filter.mjs --list                                             List existing filters
//   node scripts/gmail-filter.mjs --from "someone@x.com" --label "Nume"              DRY-RUN: preview filter
//   node scripts/gmail-filter.mjs --from "someone@x.com" --label "Nume" --apply      Create filter
//   node scripts/gmail-filter.mjs --delete <filterId>                                Delete filter by ID
//
// Notes:
// - Native filter applies to FUTURE mail only. Use gmail-label.mjs --apply for retroactive labeling.
// - Reversible: any filter can be deleted via --delete or Gmail Settings UI.

import fs from 'fs';
import path from 'path';
import os from 'os';

const KEYS_PATH = path.join(os.homedir(), '.gmail-mcp', 'gcp-oauth.keys.json');
const TOKEN_PATH = path.join(os.homedir(), '.gmail-mcp', 'credentials.json');

function arg(name) {
  const i = process.argv.indexOf(name);
  return i !== -1 ? (process.argv[i + 1] ?? true) : undefined;
}
const doList = process.argv.includes('--list');
const doApply = process.argv.includes('--apply');
const fromArg = arg('--from');
const toArg = arg('--to');
const subjectArg = arg('--subject');
const queryArg = arg('--query');
const labelName = arg('--label');
const deleteId = arg('--delete');

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

async function findLabelId(name) {
  const all = await gapi(token, 'labels');
  const found = (all.labels || []).find(l => l.name === name);
  if (!found) throw new Error(`Label "${name}" not found. Create it first via gmail-label.mjs.`);
  return found.id;
}

if (doList) {
  const res = await gapi(token, 'settings/filters');
  const filters = res.filter || [];
  console.log(`Existing filters: ${filters.length}`);
  for (const f of filters) {
    const c = f.criteria || {};
    const a = f.action || {};
    const crit = Object.entries(c).map(([k, v]) => `${k}=${v}`).join(', ');
    const act = [
      ...(a.addLabelIds || []).map(id => `+${id}`),
      ...(a.removeLabelIds || []).map(id => `-${id}`),
      a.forward ? `forward:${a.forward}` : null,
    ].filter(Boolean).join(', ');
    console.log(`- ${f.id} | criteria: ${crit || '(none)'} | action: ${act || '(none)'}`);
  }
  process.exit(0);
}

if (deleteId) {
  await gapi(token, `settings/filters/${deleteId}`, 'DELETE');
  console.log(`DELETED filter ${deleteId}`);
  process.exit(0);
}

if (!labelName || (!fromArg && !toArg && !subjectArg && !queryArg)) {
  console.error('Need --label "Name" and at least one of --from/--to/--subject/--query. Or use --list / --delete <id>.');
  process.exit(2);
}

const labelId = await findLabelId(labelName);

const criteria = {};
if (fromArg) criteria.from = fromArg;
if (toArg) criteria.to = toArg;
if (subjectArg) criteria.subject = subjectArg;
if (queryArg) criteria.query = queryArg;

const body = { criteria, action: { addLabelIds: [labelId] } };

console.log('Filter to create:');
console.log(JSON.stringify(body, null, 2));

if (!doApply) {
  console.log('\nDRY-RUN. Add --apply to create the filter.');
  process.exit(0);
}

const created = await gapi(token, 'settings/filters', 'POST', body);
console.log(`\nCREATED filter ${created.id}`);
console.log(JSON.stringify(created, null, 2));
