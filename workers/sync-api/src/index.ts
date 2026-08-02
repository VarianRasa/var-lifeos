const PREFIX = '/sync';
const RESET_URL = 'https://api.var.app/sync/reset-password';
const SENDER = 'no-reply@var.app';
const RESET_TTL_MS = 20 * 60 * 1000;
const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const BACKUP_MAX = 10 * 1024 * 1024;
const ATTACHMENT_MAX = 25 * 1024 * 1024;
const PBKDF2_ITERATIONS = 600000;
const encoder = new TextEncoder();

type Json = Record<string, unknown>;
type UserRow = { id: string; email: string; display_name: string; password_hash: string; password_salt: string; password_iterations: number };
type SessionRow = { user_id: string; expires_at: number };
type MetadataRow = { object_key: string; sha256: string; byte_length: number; content_type: string; file_name: string | null; tombstone_version: string | null; updated_at: number };
type ResetRow = { user_id: string; expires_at: number; used_at: number | null };

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const origin = request.headers.get('Origin');
    const cors = corsHeaders(origin, env.ALLOWED_ORIGINS);
    if (request.method === 'OPTIONS') return preflight(origin, cors);
    try {
      const response = await route(request, env);
      return withHeaders(response, cors);
    } catch (error) {
      if (error instanceof HttpError) return withHeaders(jsonError(error.status, error.code, error.message), cors);
      console.error(JSON.stringify({ message: 'sync request failed', path: new URL(request.url).pathname, error: error instanceof Error ? error.message : String(error) }));
      return withHeaders(jsonError(500, 'internal-error', 'Request failed.'), cors);
    }
  },
} satisfies ExportedHandler<Env>;

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith(`${PREFIX}/`) && url.pathname !== PREFIX) throw new HttpError(404, 'not-found', 'Route not found.');
  const path = url.pathname.slice(PREFIX.length) || '/';
  if (path === '/auth/register' && request.method === 'POST') return register(request, env);
  if (path === '/auth/sign-in' && request.method === 'POST') return signIn(request, env);
  if (path === '/auth/sign-out' && request.method === 'POST') return signOut(request, env);
  if (path === '/auth/password-reset' && request.method === 'POST') return requestReset(request, env);
  if (path === '/reset-password' && request.method === 'GET') return resetPage(url);
  if (path === '/reset-password' && request.method === 'POST') return resetPassword(request, env);
  if (path === '/capabilities' && request.method === 'GET') return capabilities(request, env);
  const backup = path.match(/^\/users\/([^/]+)\/mindmap-backup\/latest$/);
  if (backup && (request.method === 'GET' || request.method === 'PUT')) return backupRoute(request, env, decodeSegment(backup[1]));
  const attachment = path.match(/^\/attachments\/([^/]+)$/);
  if (attachment && ['HEAD', 'GET', 'PUT', 'DELETE'].includes(request.method)) return attachmentRoute(request, env, decodeSegment(attachment[1]));
  throw new HttpError(404, 'not-found', 'Route not found.');
}

async function register(request: Request, env: Env): Promise<Response> {
  const body = await jsonBody(request, 16 * 1024);
  const email = emailValue(body.email);
  const password = passwordValue(body.password);
  const displayName = textValue(body.displayName, 100, false);
  const id = crypto.randomUUID();
  const now = Date.now();
  const passwordData = await hashPassword(password);
  try {
    await env.DB.prepare('INSERT INTO users (id, email, display_name, password_hash, password_salt, password_iterations, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
      .bind(id, email, displayName, passwordData.hash, passwordData.salt, passwordData.iterations, now, now).run();
  } catch (error) {
    if (String(error).toLowerCase().includes('unique')) throw new HttpError(409, 'email-in-use', 'Account already exists.');
    throw error;
  }
  return authResponse(env, { id, email, display_name: displayName }, 201);
}

async function signIn(request: Request, env: Env): Promise<Response> {
  const body = await jsonBody(request, 16 * 1024);
  const email = emailValue(body.email);
  const password = passwordValue(body.password);
  const user = await env.DB.prepare('SELECT id, email, display_name, password_hash, password_salt, password_iterations FROM users WHERE email = ?').bind(email).first<UserRow>();
  if (!user || !await verifyPassword(password, user)) throw new HttpError(401, 'invalid-credentials', 'Email or password is invalid.');
  return authResponse(env, user, 200);
}

async function authResponse(env: Env, user: Pick<UserRow, 'id' | 'email' | 'display_name'>, status: number): Promise<Response> {
  const token = randomToken();
  const now = Date.now();
  await env.DB.prepare('INSERT INTO sessions (token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)').bind(await sha256(token), user.id, now + SESSION_TTL_MS, now).run();
  return Response.json({ user: { id: user.id, email: user.email, displayName: user.display_name }, accessToken: token, expiresAt: new Date(now + SESSION_TTL_MS).toISOString() }, { status });
}

async function signOut(request: Request, env: Env): Promise<Response> {
  const token = bearer(request);
  await requireUser(request, env);
  await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(await sha256(token)).run();
  return new Response(null, { status: 204 });
}

async function requestReset(request: Request, env: Env): Promise<Response> {
  const body = await jsonBody(request, 16 * 1024);
  const email = emailValue(body.email);
  const user = await env.DB.prepare('SELECT id, email FROM users WHERE email = ?').bind(email).first<{ id: string; email: string }>();
  if (user) {
    const token = randomToken();
    const now = Date.now();
    await env.DB.batch([
      env.DB.prepare('DELETE FROM reset_tokens WHERE user_id = ? OR expires_at <= ?').bind(user.id, now),
      env.DB.prepare('INSERT INTO reset_tokens (token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)').bind(await sha256(token), user.id, now + RESET_TTL_MS, now),
    ]);
    const link = `${RESET_URL}?token=${encodeURIComponent(token)}`;
    await env.EMAIL.send({
      to: user.email,
      from: { email: SENDER, name: 'Var' },
      subject: 'Reset your Var password',
      text: `Reset your Var password within 20 minutes: ${link}\n\nIf you did not request this, ignore this email.`,
      html: `<p>Reset your Var password within 20 minutes.</p><p><a href="${escapeHtml(link)}">Reset password</a></p><p>If you did not request this, ignore this email.</p>`,
    });
  }
  return Response.json({ accepted: true }, { status: 202 });
}

function resetPage(url: URL): Response {
  const token = url.searchParams.get('token') ?? '';
  const safeToken = /^[A-Za-z0-9_-]{43}$/.test(token) ? token : '';
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>Reset Var password</title><style>body{background:#111;color:#eee;font:16px system-ui;margin:0;padding:2rem}main{max-width:28rem;margin:auto}label,input,button{display:block;width:100%;box-sizing:border-box}input,button{font:inherit;padding:.8rem;margin:.5rem 0 1rem}button{cursor:pointer}</style></head><body><main><h1>Reset password</h1><form method="post" action="${RESET_URL}"><input type="hidden" name="token" value="${escapeHtml(safeToken)}"><label for="password">New password</label><input id="password" name="password" type="password" minlength="12" maxlength="128" autocomplete="new-password" required><button type="submit">Reset password</button></form></main></body></html>`;
  return new Response(html, { headers: { 'Content-Type': 'text/html; charset=utf-8', 'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'", 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'Cache-Control': 'no-store' } });
}

async function resetPassword(request: Request, env: Env): Promise<Response> {
  const body = await bodyRecord(request, 16 * 1024);
  const token = tokenValue(body.token);
  const password = passwordValue(body.password);
  const tokenHash = await sha256(token);
  const now = Date.now();
  const reset = await env.DB.prepare('SELECT user_id, expires_at, used_at FROM reset_tokens WHERE token_hash = ?').bind(tokenHash).first<ResetRow>();
  if (!reset || reset.used_at !== null || reset.expires_at <= now) throw new HttpError(400, 'invalid-reset-token', 'Reset link is invalid or expired.');
  const passwordData = await hashPassword(password);
  const results = await env.DB.batch([
    env.DB.prepare('UPDATE users SET password_hash = ?, password_salt = ?, password_iterations = ?, updated_at = ? WHERE id = ? AND EXISTS (SELECT 1 FROM reset_tokens WHERE token_hash = ? AND user_id = ? AND used_at IS NULL AND expires_at > ?)').bind(passwordData.hash, passwordData.salt, passwordData.iterations, now, reset.user_id, tokenHash, reset.user_id, now),
    env.DB.prepare('UPDATE reset_tokens SET used_at = ? WHERE token_hash = ? AND user_id = ? AND used_at IS NULL AND expires_at > ?').bind(now, tokenHash, reset.user_id, now),
    env.DB.prepare('DELETE FROM sessions WHERE user_id = ? AND EXISTS (SELECT 1 FROM reset_tokens WHERE token_hash = ? AND user_id = ? AND used_at = ?)').bind(reset.user_id, tokenHash, reset.user_id, now),
  ]);
  if ((results[0].meta.changes ?? 0) !== 1 || (results[1].meta.changes ?? 0) !== 1) throw new HttpError(400, 'invalid-reset-token', 'Reset link is invalid or expired.');
  if (request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) return Response.json({ reset: true });
  return new Response('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Password reset</title></head><body><main><h1>Password reset</h1><p>You can return to Var and sign in.</p></main></body></html>', { headers: { 'Content-Type': 'text/html; charset=utf-8', 'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'", 'X-Content-Type-Options': 'nosniff', 'Cache-Control': 'no-store' } });
}

async function capabilities(request: Request, env: Env): Promise<Response> {
  await requireUser(request, env);
  return Response.json({ attachments: { version: 1, upload: true, download: true, delete: true, maxBytes: ATTACHMENT_MAX }, backup: { maxBytes: BACKUP_MAX } });
}

async function backupRoute(request: Request, env: Env, requestedUserId: string): Promise<Response> {
  const user = await requireUser(request, env);
  if (user.id !== requestedUserId) throw new HttpError(403, 'forbidden', 'Resource belongs to another user.');
  const key = `backups/${user.id}/latest.json`;
  if (request.method === 'GET') {
    const object = await env.STORAGE.get(key);
    if (!object) throw new HttpError(404, 'not-found', 'Backup not found.');
    return new Response(object.body, { headers: { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': String(object.size), 'ETag': object.httpEtag, 'Cache-Control': 'no-store' } });
  }
  const bytes = await boundedBody(request, BACKUP_MAX, true);
  try { JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); } catch { throw new HttpError(400, 'invalid-backup', 'Backup must be valid UTF-8 JSON.'); }
  const checksum = await sha256Bytes(bytes.buffer);
  await env.STORAGE.put(key, bytes.buffer, { httpMetadata: { contentType: 'application/json; charset=utf-8' }, customMetadata: { sha256: checksum } });
  await upsertMetadata(env, user.id, 'backup', 'latest', key, checksum, bytes.byteLength, 'application/json; charset=utf-8', null, null);
  return new Response(null, { status: 204 });
}

async function attachmentRoute(request: Request, env: Env, id: string): Promise<Response> {
  validateAttachmentId(id);
  const user = await requireUser(request, env);
  const metadata = await env.DB.prepare("SELECT object_key, sha256, byte_length, content_type, file_name, tombstone_version, updated_at FROM object_metadata WHERE user_id = ? AND object_type = 'attachment' AND object_id = ?").bind(user.id, id).first<MetadataRow>();
  if (request.method === 'PUT') {
    const input = attachmentHeaders(request, id);
    const bytes = await boundedBody(request, ATTACHMENT_MAX, true);
    if (bytes.byteLength !== input.byteLength || await sha256Bytes(bytes.buffer) !== input.sha256) throw new HttpError(400, 'integrity-error', 'Attachment checksum or length does not match.');
    const key = `attachments/${user.id}/${id}`;
    await env.STORAGE.put(key, bytes.buffer, { httpMetadata: { contentType: input.contentType }, customMetadata: { sha256: input.sha256, fileName: input.fileName } });
    await upsertMetadata(env, user.id, 'attachment', id, key, input.sha256, input.byteLength, input.contentType, input.fileName, null);
    return new Response(null, { status: metadata ? 204 : 201 });
  }
  if (!metadata) throw new HttpError(404, 'not-found', 'Attachment not found.');
  if (request.method === 'DELETE') {
    const tombstone = headerValue(request, 'x-var-attachment-tombstone', /^[A-Za-z0-9._:-]{1,128}$/);
    await env.STORAGE.delete(metadata.object_key);
    await env.DB.prepare("DELETE FROM object_metadata WHERE user_id = ? AND object_type = 'attachment' AND object_id = ? AND ? <> ''").bind(user.id, id, tombstone).run();
    return new Response(null, { status: 204 });
  }
  const object = await env.STORAGE.get(metadata.object_key);
  if (!object) throw new HttpError(404, 'not-found', 'Attachment not found.');
  const headers = metadataHeaders(id, metadata);
  if (request.method === 'HEAD') return new Response(null, { headers });
  return new Response(object.body, { headers });
}

async function requireUser(request: Request, env: Env): Promise<{ id: string; email: string }> {
  const hash = await sha256(bearer(request));
  const session = await env.DB.prepare('SELECT user_id, expires_at FROM sessions WHERE token_hash = ?').bind(hash).first<SessionRow>();
  if (!session || session.expires_at <= Date.now()) {
    if (session) await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(hash).run();
    throw new HttpError(401, 'unauthorized', 'Valid session required.');
  }
  const user = await env.DB.prepare('SELECT id, email FROM users WHERE id = ?').bind(session.user_id).first<{ id: string; email: string }>();
  if (!user) throw new HttpError(401, 'unauthorized', 'Valid session required.');
  return user;
}

async function upsertMetadata(env: Env, userId: string, type: string, id: string, key: string, checksum: string, length: number, contentType: string, fileName: string | null, tombstone: string | null): Promise<void> {
  await env.DB.prepare('INSERT INTO object_metadata (user_id, object_type, object_id, object_key, sha256, byte_length, content_type, file_name, tombstone_version, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(user_id, object_type, object_id) DO UPDATE SET object_key = excluded.object_key, sha256 = excluded.sha256, byte_length = excluded.byte_length, content_type = excluded.content_type, file_name = excluded.file_name, tombstone_version = excluded.tombstone_version, updated_at = excluded.updated_at')
    .bind(userId, type, id, key, checksum, length, contentType, fileName, tombstone, Date.now()).run();
}

export async function hashPassword(password: string, salt = randomToken(16), iterations = PBKDF2_ITERATIONS): Promise<{ hash: string; salt: string; iterations: number }> {
  const key = await crypto.subtle.importKey('raw', encoder.encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: fromBase64Url(salt).buffer, iterations }, key, 256);
  return { hash: toBase64Url(new Uint8Array(bits)), salt, iterations };
}

export async function verifyPassword(password: string, stored: Pick<UserRow, 'password_hash' | 'password_salt' | 'password_iterations'>): Promise<boolean> {
  const result = await hashPassword(password, stored.password_salt, stored.password_iterations);
  return timingSafeText(result.hash, stored.password_hash);
}

export function validateAttachmentId(value: string): string {
  if (!/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(value) || value === '.' || value === '..') throw new HttpError(400, 'invalid-attachment-id', 'Attachment ID is invalid.');
  return value;
}

function attachmentHeaders(request: Request, id: string): { sha256: string; byteLength: number; contentType: string; fileName: string } {
  if (headerValue(request, 'x-var-attachment-schema-version', /^1$/) !== '1') throw new HttpError(400, 'invalid-metadata', 'Attachment schema is invalid.');
  if (headerValue(request, 'x-var-attachment-id', /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/) !== id) throw new HttpError(400, 'invalid-metadata', 'Attachment ID does not match.');
  const sha = headerValue(request, 'x-var-attachment-sha256', /^[a-fA-F0-9]{64}$/).toLowerCase();
  const length = Number(headerValue(request, 'x-var-attachment-byte-length', /^\d{1,8}$/));
  if (!Number.isSafeInteger(length) || length <= 0 || length > ATTACHMENT_MAX) throw new HttpError(400, 'invalid-metadata', 'Attachment length is invalid.');
  const contentType = request.headers.get('Content-Type')?.toLowerCase().trim() ?? '';
  if (!/^[a-z0-9][a-z0-9!#$&^_.+-]*\/[a-z0-9][a-z0-9!#$&^_.+-]*$/.test(contentType)) throw new HttpError(400, 'invalid-metadata', 'Attachment content type is invalid.');
  let fileName: string;
  try { fileName = decodeURIComponent(headerValue(request, 'x-var-attachment-file-name', /^.{1,765}$/)); } catch { throw new HttpError(400, 'invalid-metadata', 'Attachment filename is invalid.'); }
  if (!fileName.trim() || fileName.length > 255 || /[\\/\u0000-\u001f\u007f"]/u.test(fileName) || fileName === '.' || fileName === '..') throw new HttpError(400, 'invalid-metadata', 'Attachment filename is invalid.');
  return { sha256: sha, byteLength: length, contentType, fileName };
}

function metadataHeaders(id: string, metadata: MetadataRow): Headers {
  return new Headers({ 'Content-Type': metadata.content_type, 'Content-Length': String(metadata.byte_length), 'x-var-attachment-schema-version': '1', 'x-var-attachment-id': id, 'x-var-attachment-sha256': metadata.sha256, 'x-var-attachment-byte-length': String(metadata.byte_length), 'x-var-attachment-file-name': encodeURIComponent(metadata.file_name ?? ''), 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' });
}

async function jsonBody(request: Request, max: number): Promise<Json> {
  if (!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) throw new HttpError(415, 'unsupported-media-type', 'JSON required.');
  const bytes = await boundedBody(request, max, false);
  try { return record(JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes))); } catch { throw new HttpError(400, 'invalid-json', 'JSON body is invalid.'); }
}

async function bodyRecord(request: Request, max: number): Promise<Json> {
  if (request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) return jsonBody(request, max);
  if (!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/x-www-form-urlencoded')) throw new HttpError(415, 'unsupported-media-type', 'JSON or form data required.');
  const bytes = await boundedBody(request, max, false);
  const params = new URLSearchParams(new TextDecoder().decode(bytes));
  return Object.fromEntries(params.entries());
}

async function boundedBody(request: Request, max: number, requireLength: boolean): Promise<Uint8Array<ArrayBuffer>> {
  const rawLength = request.headers.get('Content-Length');
  if (requireLength && rawLength === null) throw new HttpError(411, 'length-required', 'Content-Length required.');
  const expected = rawLength === null ? null : Number(rawLength);
  if (expected !== null && (!Number.isSafeInteger(expected) || expected < 0)) throw new HttpError(400, 'invalid-length', 'Content-Length is invalid.');
  if (expected !== null && expected > max) throw new HttpError(413, 'payload-too-large', 'Payload is too large.');
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks: Uint8Array<ArrayBuffer>[] = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > max) { await reader.cancel(); throw new HttpError(413, 'payload-too-large', 'Payload is too large.'); }
    chunks.push(Uint8Array.from(value));
  }
  if (expected !== null && expected !== length) throw new HttpError(400, 'invalid-length', 'Content-Length does not match body.');
  const result = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.byteLength; }
  return result;
}

function corsHeaders(origin: string | null, configured: string): Headers {
  const headers = new Headers({ Vary: 'Origin' });
  if (origin && configured.split(',').map((item) => item.trim()).includes(origin)) {
    headers.set('Access-Control-Allow-Origin', origin);
    headers.set('Access-Control-Allow-Methods', 'GET,HEAD,PUT,POST,DELETE,OPTIONS');
    headers.set('Access-Control-Allow-Headers', 'Authorization,Content-Type,X-Var-Attachment-Schema-Version,X-Var-Attachment-Id,X-Var-Attachment-Sha256,X-Var-Attachment-Byte-Length,X-Var-Attachment-File-Name,X-Var-Attachment-Tombstone');
    headers.set('Access-Control-Max-Age', '86400');
  }
  return headers;
}

function preflight(origin: string | null, cors: Headers): Response {
  if (!origin || !cors.has('Access-Control-Allow-Origin')) return jsonError(403, 'origin-not-allowed', 'Origin not allowed.');
  return new Response(null, { status: 204, headers: cors });
}

function withHeaders(response: Response, extra: Headers): Response {
  const headers = new Headers(response.headers);
  extra.forEach((value, key) => headers.set(key, value));
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

function bearer(request: Request): string {
  const match = request.headers.get('Authorization')?.match(/^Bearer ([A-Za-z0-9_-]{43})$/);
  if (!match) throw new HttpError(401, 'unauthorized', 'Valid session required.');
  return match[1];
}

function emailValue(value: unknown): string {
  const email = typeof value === 'string' ? value.trim().toLowerCase() : '';
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new HttpError(400, 'invalid-email', 'Email is invalid.');
  return email;
}

function passwordValue(value: unknown): string {
  if (typeof value !== 'string' || value.length < 12 || value.length > 128) throw new HttpError(400, 'invalid-password', 'Password must contain 12 to 128 characters.');
  return value;
}

function tokenValue(value: unknown): string {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(value)) throw new HttpError(400, 'invalid-reset-token', 'Reset link is invalid or expired.');
  return value;
}

function textValue(value: unknown, max: number, required: boolean): string {
  const text = typeof value === 'string' ? value.trim() : '';
  if (text.length > max || (required && !text)) throw new HttpError(400, 'invalid-value', 'Value is invalid.');
  return text;
}

function headerValue(request: Request, name: string, pattern: RegExp): string {
  const value = request.headers.get(name) ?? '';
  if (!pattern.test(value)) throw new HttpError(400, 'invalid-metadata', `${name} is invalid.`);
  return value;
}

function decodeSegment(value: string): string {
  try { return decodeURIComponent(value); } catch { throw new HttpError(400, 'invalid-path', 'Path is invalid.'); }
}

function record(value: unknown): Json {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Object required.');
  return value as Json;
}

export function randomToken(bytes = 32): string {
  const value = new Uint8Array(bytes);
  crypto.getRandomValues(value);
  return toBase64Url(value);
}

export async function sha256(value: string): Promise<string> { return sha256Bytes(encoder.encode(value)); }
export async function sha256Bytes(value: BufferSource): Promise<string> { return [...new Uint8Array(await crypto.subtle.digest('SHA-256', value))].map((byte) => byte.toString(16).padStart(2, '0')).join(''); }
function timingSafeText(left: string, right: string): boolean { const a = encoder.encode(left); const b = encoder.encode(right); let difference = a.byteLength ^ b.byteLength; const length = Math.max(a.byteLength, b.byteLength); for (let index = 0; index < length; index += 1) difference |= (a[index] ?? 0) ^ (b[index] ?? 0); return difference === 0; }
function toBase64Url(bytes: Uint8Array): string { let binary = ''; for (const byte of bytes) binary += String.fromCharCode(byte); return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, ''); }
function fromBase64Url(value: string): Uint8Array<ArrayBuffer> { const base64 = value.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(value.length / 4) * 4, '='); return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0)); }
function escapeHtml(value: string): string { return value.replace(/[&<>'"]/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[character] ?? character); }
function jsonError(status: number, code: string, message: string): Response { return Response.json({ error: { code, message } }, { status, headers: { 'Cache-Control': 'no-store' } }); }

class HttpError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}
