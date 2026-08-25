#!/usr/bin/env node
// One-time Gmail OAuth flow — saves token to ~/.gmail-mcp/credentials.json
import http from 'http';
import { exec } from 'child_process';
import fs from 'fs';
import path from 'path';
import os from 'os';

const KEYS_PATH = path.join(os.homedir(), '.gmail-mcp', 'gcp-oauth.keys.json');
const TOKEN_PATH = path.join(os.homedir(), '.gmail-mcp', 'credentials.json');
const PORT = 8085;
const REDIRECT_URI = `http://localhost:${PORT}/oauth2callback`;
const SCOPES = [
  'https://www.googleapis.com/auth/gmail.modify',
  'https://www.googleapis.com/auth/gmail.compose',
  'https://www.googleapis.com/auth/gmail.send',
  'https://www.googleapis.com/auth/gmail.settings.basic',
].join(' ');

const keys = JSON.parse(fs.readFileSync(KEYS_PATH, 'utf8'));
const { client_id, client_secret } = keys.installed;

const authUrl =
  `https://accounts.google.com/o/oauth2/v2/auth` +
  `?client_id=${encodeURIComponent(client_id)}` +
  `&redirect_uri=${encodeURIComponent(REDIRECT_URI)}` +
  `&response_type=code` +
  `&scope=${encodeURIComponent(SCOPES)}` +
  `&access_type=offline` +
  `&prompt=consent`;

console.log('\nDeschide URL-ul în browser (se va deschide automat):\n' + authUrl + '\n');
exec(`open "${authUrl}"`);

const server = http.createServer(async (req, res) => {
  if (!req.url.startsWith('/oauth2callback')) {
    res.writeHead(404); res.end('Not found'); return;
  }
  const code = new URL(req.url, `http://localhost:${PORT}`).searchParams.get('code');
  if (!code) {
    res.writeHead(400); res.end('Lipseste codul de autorizare.'); return;
  }

  // Exchange code for token
  const params = new URLSearchParams({
    code, client_id, client_secret,
    redirect_uri: REDIRECT_URI,
    grant_type: 'authorization_code',
  });

  try {
    const resp = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString(),
    });
    const token = await resp.json();
    if (token.error) throw new Error(token.error_description || token.error);

    fs.mkdirSync(path.dirname(TOKEN_PATH), { recursive: true });
    fs.writeFileSync(TOKEN_PATH, JSON.stringify(token, null, 2));

    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end('<h2>✅ Autorizare reușită! Poți închide această fereastră.</h2>');
    console.log('\n✅ Token salvat la: ' + TOKEN_PATH);
    console.log('Refresh token: ' + token.refresh_token?.slice(0, 20) + '...');
    server.close();
    process.exit(0);
  } catch (err) {
    res.writeHead(500); res.end('Eroare: ' + err.message);
    console.error('Eroare la schimbul de token:', err.message);
    server.close();
    process.exit(1);
  }
});

server.listen(PORT, () => console.log(`Server auth pornit pe portul ${PORT}...`));
