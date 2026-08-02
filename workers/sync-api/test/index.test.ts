import assert from 'node:assert/strict';
import test from 'node:test';
import worker, { hashPassword, randomToken, sha256, validateAttachmentId, verifyPassword } from '../src/index.ts';

test('tokens are random, 256-bit, and hash to SHA-256', async () => {
  const first = randomToken();
  const second = randomToken();
  assert.match(first, /^[A-Za-z0-9_-]{43}$/);
  assert.notEqual(first, second);
  assert.match(await sha256(first), /^[a-f0-9]{64}$/);
});

test('PBKDF2 password hashes use salt and verify exactly', async () => {
  const first = await hashPassword('correct horse battery staple');
  const second = await hashPassword('correct horse battery staple');
  assert.equal(first.iterations, 600000);
  assert.notEqual(first.salt, second.salt);
  assert.notEqual(first.hash, second.hash);
  assert.equal(await verifyPassword('correct horse battery staple', { password_hash: first.hash, password_salt: first.salt, password_iterations: first.iterations }), true);
  assert.equal(await verifyPassword('wrong password value', { password_hash: first.hash, password_salt: first.salt, password_iterations: first.iterations }), false);
});

test('attachment IDs reject path traversal and unsafe text', () => {
  assert.equal(validateAttachmentId('file_01:a-b.c'), 'file_01:a-b.c');
  for (const value of ['../secret', '.', '..', 'a/b', 'space here']) assert.throws(() => validateAttachmentId(value));
});

test('reset page escapes invalid token and sets browser protections', async () => {
  const response = await worker.fetch(new Request('https://api.var.app/sync/reset-password?token=%22%3E%3Cscript%3E'), { ALLOWED_ORIGINS: 'https://var.app' } as Env);
  const html = await response.text();
  assert.equal(response.status, 200);
  assert.match(response.headers.get('Content-Security-Policy') ?? '', /form-action 'self'/);
  assert.doesNotMatch(html, /<script>/);
  assert.match(html, /name="token" value=""/);
});

test('CORS reflects only exact configured origin', async () => {
  const allowed = await worker.fetch(new Request('https://api.var.app/sync/reset-password', { headers: { Origin: 'https://var.app' } }), { ALLOWED_ORIGINS: 'https://var.app' } as Env);
  const denied = await worker.fetch(new Request('https://api.var.app/sync/reset-password', { headers: { Origin: 'https://evil.var.app' } }), { ALLOWED_ORIGINS: 'https://var.app' } as Env);
  assert.equal(allowed.headers.get('Access-Control-Allow-Origin'), 'https://var.app');
  assert.equal(denied.headers.get('Access-Control-Allow-Origin'), null);
});
