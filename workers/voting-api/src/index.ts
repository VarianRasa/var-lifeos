const encoder = new TextEncoder();
const decoder = new TextDecoder();
const idPattern = /^[A-Za-z0-9_-]{1,128}$/;

export type WorkerEnv = Env;
type Claims = { aud?: string; exp?: number; iat?: number; iss?: string; sub?: string };
type Jwk = JsonWebKey & { kid?: string };
type FirestoreValue = { arrayValue?: { values?: FirestoreValue[] }; booleanValue?: boolean; integerValue?: string; mapValue?: { fields?: Record<string, FirestoreValue> }; stringValue?: string };
type Ballot = { choices: string[]; mutationId: string };
type BoardAuthority = { maxVotes: number; options: string[] };
type Session = { max_votes: number; options_json: string; room_id: string };

class HttpError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function base64url(value: string): Uint8Array {
  const base64 = value.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(value.length / 4) * 4, '=');
  const binary = atob(base64);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function parseJsonPart<T>(value: string): T {
  return JSON.parse(decoder.decode(base64url(value))) as T;
}

async function verifyFirebaseToken(token: string, projectId: string): Promise<string> {
  const parts = token.split('.');
  if (parts.length !== 3) throw new HttpError(401, 'invalid token');
  const header = parseJsonPart<{ alg?: string; kid?: string }>(parts[0]);
  const claims = parseJsonPart<Claims>(parts[1]);
  if (header.alg !== 'RS256' || !header.kid) throw new HttpError(401, 'invalid token');
  const now = Math.floor(Date.now() / 1000);
  if (claims.aud !== projectId || claims.iss !== `https://securetoken.google.com/${projectId}` || !claims.sub || claims.sub.length > 128 || !claims.exp || claims.exp <= now || !claims.iat || claims.iat > now + 60) throw new HttpError(401, 'invalid token');
  const response = await fetch('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com', { cf: { cacheEverything: true, cacheTtl: 3600 } });
  if (!response.ok) throw new HttpError(503, 'identity service unavailable');
  const keys = await response.json<{ keys: Jwk[] }>();
  const jwk = keys.keys.find((key) => key.kid === header.kid);
  if (!jwk) throw new HttpError(401, 'invalid token');
  const key = await crypto.subtle.importKey('jwk', jwk, { hash: 'SHA-256', name: 'RSASSA-PKCS1-v1_5' }, false, ['verify']);
  const valid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, new Uint8Array(base64url(parts[2])).buffer, encoder.encode(`${parts[0]}.${parts[1]}`));
  if (!valid) throw new HttpError(401, 'invalid token');
  return claims.sub;
}

function fieldMap(value: FirestoreValue | undefined): Record<string, FirestoreValue> {
  return value?.mapValue?.fields ?? {};
}

function parseMember(fields: Record<string, FirestoreValue>): string {
  const role = fields.role?.stringValue;
  if (!role || !['owner', 'editor', 'commenter', 'viewer'].includes(role) || fields.active?.booleanValue === false) throw new HttpError(403, 'active room membership required');
  return role;
}

function parseBoardAuthority(fields: Record<string, FirestoreValue>, sessionId: string): BoardAuthority {
  const payload = fieldMap(fields.payload);
  const voting = fieldMap(payload.votingSession);
  if (voting.status?.stringValue !== 'active' || voting.sessionId?.stringValue !== sessionId) throw new HttpError(409, 'session inactive');
  const maxVotes = Number(voting.maxVotesPerParticipant?.integerValue);
  const objects = payload.objects?.arrayValue?.values ?? [];
  const options = objects.map((value) => fieldMap(value).id?.stringValue).filter((id): id is string => Boolean(id && idPattern.test(id)));
  if (!Number.isInteger(maxVotes) || maxVotes < 1 || maxVotes > 100 || options.length === 0 || new Set(options).size !== options.length) throw new HttpError(409, 'invalid board voting metadata');
  return { maxVotes, options };
}

async function firestoreGet(env: WorkerEnv, token: string, path: string): Promise<Record<string, FirestoreValue>> {
  const url = `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/databases/(default)/documents/${path}`;
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (response.status === 401) throw new HttpError(401, 'invalid token');
  if (response.status === 403 || response.status === 404) throw new HttpError(403, 'resource access denied');
  if (!response.ok) throw new HttpError(503, 'authorization service unavailable');
  return (await response.json<{ fields?: Record<string, FirestoreValue> }>()).fields ?? {};
}

async function authorize(request: Request, env: WorkerEnv, roomId: string, boardId: string, sessionId: string): Promise<{ authority: BoardAuthority; uid: string }> {
  const authorization = request.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) throw new HttpError(401, 'authentication required');
  const token = authorization.slice(7);
  const uid = await verifyFirebaseToken(token, env.FIREBASE_PROJECT_ID);
  const member = await firestoreGet(env, token, `rooms/${encodeURIComponent(roomId)}/members/${encodeURIComponent(uid)}`);
  parseMember(member);
  const board = await firestoreGet(env, token, `rooms/${encodeURIComponent(roomId)}/boards/${encodeURIComponent(boardId)}`);
  return { authority: parseBoardAuthority(board, sessionId), uid };
}

function parseBallot(value: unknown, roomId: string, boardId: string, sessionId: string, options: string[], maxVotes: number): Ballot {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new HttpError(400, 'invalid ballot');
  const record = value as Record<string, unknown>;
  if (record.roomId !== roomId || record.boardId !== boardId || record.sessionId !== sessionId || !idPattern.test(String(record.mutationId ?? '')) || !Array.isArray(record.choices)) throw new HttpError(400, 'invalid ballot');
  const choices = record.choices;
  if (choices.length > maxVotes || choices.some((choice) => typeof choice !== 'string' || !options.includes(choice)) || new Set(choices).size !== choices.length) throw new HttpError(400, 'invalid choices');
  return { choices: [...choices].sort(), mutationId: String(record.mutationId) };
}

function cors(origin: string | null, env: WorkerEnv): HeadersInit {
  const allowed = env.ALLOWED_ORIGINS.split(',').map((value) => value.trim());
  return origin && allowed.includes(origin) ? { 'Access-Control-Allow-Origin': origin, 'Access-Control-Allow-Headers': 'Authorization, Content-Type', 'Access-Control-Allow-Methods': 'GET, PUT, OPTIONS', 'Access-Control-Max-Age': '600', Vary: 'Origin' } : {};
}

function json(data: unknown, status: number, headers: HeadersInit): Response {
  return Response.json(data, { status, headers: { ...headers, 'Cache-Control': 'no-store' } });
}

async function syncSession(env: WorkerEnv, roomId: string, sessionId: string, authority: BoardAuthority): Promise<Session> {
  const existing = await env.DB.prepare('SELECT room_id,options_json,max_votes FROM voting_sessions WHERE id=?').bind(sessionId).first<Session>();
  if (existing && existing.room_id !== roomId) throw new HttpError(409, 'session authority mismatch');
  const optionsJson = JSON.stringify(authority.options);
  await env.DB.prepare('INSERT INTO voting_sessions(id,room_id,options_json,max_votes,starts_at,ends_at) VALUES(?,?,?,?,0,2147483647) ON CONFLICT(id) DO UPDATE SET options_json=excluded.options_json,max_votes=excluded.max_votes').bind(sessionId, roomId, optionsJson, authority.maxVotes).run();
  for (const option of authority.options) await env.DB.prepare('INSERT OR IGNORE INTO vote_totals(session_id,option_id,total) VALUES(?,?,0)').bind(sessionId, option).run();
  return { room_id: roomId, options_json: optionsJson, max_votes: authority.maxVotes };
}

async function putBallot(request: Request, env: WorkerEnv, roomId: string, boardId: string, sessionId: string, session: Session, uid: string): Promise<object> {
  if (Number(request.headers.get('Content-Length') ?? 0) > 8192) throw new HttpError(413, 'body too large');
  const ballot = parseBallot(await request.json(), roomId, boardId, sessionId, JSON.parse(session.options_json) as string[], session.max_votes);
  const now = Math.floor(Date.now() / 1000);
  const choicesJson = JSON.stringify(ballot.choices);
  const receipt = JSON.stringify({ mutationId: ballot.mutationId, acceptedAt: now });
  await env.DB.batch([
    env.DB.prepare('INSERT OR IGNORE INTO processed_mutations(session_id,uid,mutation_id,created_at) VALUES(?,?,?,?)').bind(sessionId, uid, ballot.mutationId, now),
    env.DB.prepare("UPDATE vote_totals SET total=total-(CASE WHEN EXISTS(SELECT 1 FROM private_ballots b,json_each(b.choices_json) j WHERE b.session_id=? AND b.uid=? AND j.value=vote_totals.option_id) THEN 1 ELSE 0 END)+(CASE WHEN EXISTS(SELECT 1 FROM json_each(?) j WHERE j.value=vote_totals.option_id) THEN 1 ELSE 0 END) WHERE session_id=? AND EXISTS(SELECT 1 FROM processed_mutations WHERE session_id=? AND uid=? AND mutation_id=? AND applied=0)").bind(sessionId, uid, choicesJson, sessionId, sessionId, uid, ballot.mutationId),
    env.DB.prepare('INSERT INTO private_ballots(session_id,uid,choices_json,updated_at) SELECT ?,?,?,? WHERE EXISTS(SELECT 1 FROM processed_mutations WHERE session_id=? AND uid=? AND mutation_id=? AND applied=0) ON CONFLICT(session_id,uid) DO UPDATE SET choices_json=excluded.choices_json,updated_at=excluded.updated_at').bind(sessionId, uid, choicesJson, now, sessionId, uid, ballot.mutationId),
    env.DB.prepare('UPDATE processed_mutations SET applied=1,receipt_json=? WHERE session_id=? AND uid=? AND mutation_id=? AND applied=0').bind(receipt, sessionId, uid, ballot.mutationId),
  ]);
  const stored = await env.DB.prepare('SELECT receipt_json FROM processed_mutations WHERE session_id=? AND uid=? AND mutation_id=?').bind(sessionId, uid, ballot.mutationId).first<{ receipt_json: string }>();
  return JSON.parse(stored?.receipt_json ?? receipt) as object;
}

export async function handle(request: Request, env: WorkerEnv): Promise<Response> {
  const origin = request.headers.get('Origin');
  const headers = cors(origin, env);
  if (origin && !('Access-Control-Allow-Origin' in headers)) return json({ error: 'origin forbidden' }, 403, {});
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  const match = new URL(request.url).pathname.match(/^\/v1\/rooms\/([A-Za-z0-9_-]{1,128})\/boards\/([A-Za-z0-9_-]{1,128})\/sessions\/([A-Za-z0-9_-]{1,128})\/(aggregate|ballot|receipt)$/);
  if (!match) return json({ error: 'not found' }, 404, headers);
  const [, roomId, boardId, sessionId, resource] = match;
  const { authority, uid } = await authorize(request, env, roomId, boardId, sessionId);
  const session = await syncSession(env, roomId, sessionId, authority);
  if (request.method === 'PUT' && resource === 'ballot') return json(await putBallot(request, env, roomId, boardId, sessionId, session, uid), 200, headers);
  if (request.method === 'GET' && resource === 'aggregate') {
    const totals = await env.DB.prepare('SELECT option_id,total FROM vote_totals WHERE session_id=? ORDER BY option_id').bind(sessionId).all<{ option_id: string; total: number }>();
    return json({ sessionId, totals: totals.results.filter((row) => authority.options.includes(row.option_id)).map((row) => ({ optionId: row.option_id, total: row.total })) }, 200, headers);
  }
  if (request.method === 'GET' && resource === 'receipt') {
    const receipt = await env.DB.prepare('SELECT mutation_id,created_at FROM processed_mutations WHERE session_id=? AND uid=? AND applied=1 ORDER BY created_at DESC LIMIT 1').bind(sessionId, uid).first<{ created_at: number; mutation_id: string }>();
    return receipt ? json({ mutationId: receipt.mutation_id, acceptedAt: receipt.created_at }, 200, headers) : json({ error: 'not found' }, 404, headers);
  }
  return json({ error: 'method not allowed' }, 405, headers);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try { return await handle(request, env); }
    catch (error) {
      const status = error instanceof HttpError ? error.status : error instanceof SyntaxError ? 400 : 500;
      if (status === 500) console.error(JSON.stringify({ message: 'voting request failed', path: new URL(request.url).pathname }));
      return json({ error: status === 500 ? 'internal error' : (error as Error).message }, status, cors(request.headers.get('Origin'), env));
    }
  },
} satisfies ExportedHandler<Env>;

export const testing = { parseBallot, parseBoardAuthority, parseMember };
