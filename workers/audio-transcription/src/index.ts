export interface Env {
  AI: Ai;
  ALLOWED_ORIGINS?: string;
}

const maxBytes = 25 * 1024 * 1024;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const cors = corsHeaders(
      request.headers.get('Origin'),
      env.ALLOWED_ORIGINS ?? '',
    );
    if (request.method === 'OPTIONS') {
      return new Response(null, {status: 204, headers: cors});
    }
    if (request.method !== 'POST') {
      return error(405, 'method-not-allowed', 'Only POST is supported.', cors);
    }
    const contentLength = Number(request.headers.get('Content-Length') ?? '0');
    if (contentLength > maxBytes + 1024 * 64) {
      return error(413, 'audio-too-large', 'Audio must be 25 MB or less.', cors);
    }
    let form: FormData;
    try {
      form = await request.formData();
    } catch {
      return error(400, 'invalid-form', 'Multipart audio form is required.', cors);
    }
    const audio = form.get('audio');
    if (!(audio instanceof File) || audio.size === 0) {
      return error(400, 'invalid-audio', 'Audio file is required.', cors);
    }
    if (audio.size > maxBytes) {
      return error(413, 'audio-too-large', 'Audio must be 25 MB or less.', cors);
    }
    if (!audio.type.startsWith('audio/')) {
      return error(415, 'unsupported-audio', 'Audio MIME type is required.', cors);
    }
    try {
      const result: unknown = await env.AI.run('@cf/openai/whisper', {
        audio: [...new Uint8Array(await audio.arrayBuffer())],
      });
      const normalized = normalize(result);
      if (!normalized) {
        return error(
          502,
          'invalid-response',
          'Transcription model returned empty text.',
          cors,
        );
      }
      return json(normalized, cors);
    } catch (cause) {
      const message = cause instanceof Error ? cause.message : String(cause);
      return error(503, 'transcription-failed', message, cors);
    }
  },
};

export function normalize(
  value: unknown,
): {text: string; segments: TranscriptSegment[]} | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const map = value as Record<string, unknown>;
  const text = typeof map.text === 'string' ? map.text.trim() : '';
  if (!text) return null;
  const vtt = typeof map.vtt === 'string' ? map.vtt : '';
  const vttSegments = parseVtt(vtt);
  return {
    text,
    segments: vttSegments.length > 0 ? vttSegments : parseWords(map.words),
  };
}

interface TranscriptSegment {
  id: string;
  startMilliseconds: number;
  endMilliseconds: number;
  text: string;
}

export function parseVtt(value: string): TranscriptSegment[] {
  const lines = value.replaceAll('\r', '').split('\n');
  const segments: TranscriptSegment[] = [];
  for (let index = 0; index < lines.length; index += 1) {
    const timing = lines[index]?.trim() ?? '';
    if (!timing.includes(' --> ')) continue;
    const [rawStart, rawEnd] = timing.split(' --> ', 2);
    const startMilliseconds = parseTimestamp(rawStart);
    const endMilliseconds = parseTimestamp(rawEnd.split(' ')[0]);
    const textLines: string[] = [];
    while (index + 1 < lines.length && lines[index + 1].trim()) {
      index += 1;
      textLines.push(lines[index].trim());
    }
    const text = textLines.join(' ').trim();
    if (startMilliseconds === null || endMilliseconds === null || !text) continue;
    segments.push({
      id: 'segment-' + (segments.length + 1),
      startMilliseconds,
      endMilliseconds,
      text,
    });
  }
  return segments;
}

export function parseWords(value: unknown): TranscriptSegment[] {
  if (!Array.isArray(value)) return [];
  const words = value.flatMap((item) => {
    if (!item || typeof item !== 'object' || Array.isArray(item)) return [];
    const map = item as Record<string, unknown>;
    const word = typeof map.word === 'string' ? map.word.trim() : '';
    const start = Number(map.start);
    const end = Number(map.end);
    return word && Number.isFinite(start) && Number.isFinite(end) && end >= start
      ? [{word, start, end}]
      : [];
  });
  const segments: TranscriptSegment[] = [];
  for (let index = 0; index < words.length;) {
    const group = [words[index]];
    index += 1;
    while (
      index < words.length &&
      group.length < 8 &&
      !/[.!?]$/.test(group[group.length - 1].word) &&
      words[index].start - group[group.length - 1].end < 0.8
    ) {
      group.push(words[index]);
      index += 1;
    }
    segments.push({
      id: 'segment-' + (segments.length + 1),
      startMilliseconds: Math.round(group[0].start * 1000),
      endMilliseconds: Math.round(group[group.length - 1].end * 1000),
      text: group.map((item) => item.word).join(' '),
    });
  }
  return segments;
}

function parseTimestamp(value: string): number | null {
  const parts = value.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  const seconds = Number(parts.pop());
  const minutes = Number(parts.pop());
  const hours = parts.length === 1 ? Number(parts[0]) : 0;
  if (![hours, minutes, seconds].every(Number.isFinite)) return null;
  return Math.round(((hours * 60 + minutes) * 60 + seconds) * 1000);
}

function corsHeaders(origin: string | null, configured: string): HeadersInit {
  const allowed = configured.split(',').map((item) => item.trim()).filter(Boolean);
  return origin && allowed.includes(origin)
    ? {
        'Access-Control-Allow-Origin': origin,
        'Access-Control-Allow-Methods': 'POST,OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
        Vary: 'Origin',
      }
    : {};
}

function json(value: unknown, cors: HeadersInit): Response {
  return Response.json(value, {headers: cors});
}

function error(
  status: number,
  code: string,
  message: string,
  cors: HeadersInit,
): Response {
  return Response.json({error: {code, message}}, {status, headers: cors});
}
