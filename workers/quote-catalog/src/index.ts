export interface Env {
  QUOTE_API_BASE_URL?: string;
  ALLOWED_ORIGINS?: string;
}

type Json = Record<string, unknown>;
type QuoteRow = {id: string; text: string; author: string};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const origin = request.headers.get("Origin");
    const cors = corsHeaders(origin, env.ALLOWED_ORIGINS ?? "");
    if (request.method === "OPTIONS") return new Response(null, {status: 204, headers: cors});
    if (request.method !== "GET") return jsonError(405, "method-not-allowed", "Only GET is supported.", cors);
    try {
      const url = new URL(request.url);
      if (url.pathname === "/health") return json({ok: true}, cors, 60);
      const rows = await loadQuotes(env.QUOTE_API_BASE_URL ?? "https://dummyjson.com");
      const authors = buildAuthors(rows);
      if (url.pathname === "/authors/popular") {
        return json({authors: authors.slice(0, 24)}, cors, 3600);
      }
      if (url.pathname === "/authors/search") {
        const query = required(url.searchParams.get("q"), "q", 2, 80).toLowerCase();
        const page = intParam(url, "page", 1, 1000, 1);
        const limit = intParam(url, "limit", 1, 30, 20);
        const matches = authors.filter((author) => String(author.name).toLowerCase().includes(query));
        return json(pageResult("authors", matches, page, limit), cors, 300);
      }
      if (url.pathname === "/quotes") {
        const authorSlug = required(url.searchParams.get("author"), "author", 1, 120);
        const page = intParam(url, "page", 1, 1000, 1);
        const limit = intParam(url, "limit", 1, 30, 20);
        const matches = rows
          .filter((row) => slugify(row.author) === authorSlug)
          .map((row) => ({
            id: row.id,
            text: row.text,
            authorName: row.author,
            authorSlug,
            tags: [],
            sourceUrl: `https://dummyjson.com/quotes/${encodeURIComponent(row.id)}`,
            provider: "dummyjson",
          }));
        return json(pageResult("quotes", matches, page, limit), cors, 900);
      }
      return jsonError(404, "not-found", "Route not found.", cors);
    } catch (error) {
      if (error instanceof InputError) return jsonError(400, "invalid-argument", error.message, cors);
      if (error instanceof DOMException && error.name === "AbortError") return jsonError(504, "timeout", "Quote provider timed out.", cors);
      return jsonError(503, "unavailable", "Quote catalog is unavailable.", cors);
    }
  },
};

class InputError extends Error {}

async function loadQuotes(baseUrl: string): Promise<QuoteRow[]> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    const response = await fetch(new URL("/quotes?limit=0", baseUrl), {
      headers: {Accept: "application/json"},
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`Upstream ${response.status}`);
    const value: unknown = await response.json();
    const map = record(value);
    return array(map.quotes).slice(0, 5000).map((item) => {
      const quote = record(item);
      return {
        id: String(quote.id),
        text: requiredText(quote.quote, 4000),
        author: requiredText(quote.author),
      };
    });
  } finally {
    clearTimeout(timer);
  }
}

function buildAuthors(rows: QuoteRow[]): Json[] {
  const counts = new Map<string, number>();
  for (const row of rows) counts.set(row.author, (counts.get(row.author) ?? 0) + 1);
  return [...counts.entries()]
    .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
    .map(([name, quoteCount]) => ({id: slugify(name), name, slug: slugify(name), description: "", quoteCount}));
}

function pageResult(key: "authors" | "quotes", values: Json[], page: number, limit: number): Json {
  const totalPages = values.length === 0 ? 0 : Math.ceil(values.length / limit);
  const start = (page - 1) * limit;
  return {[key]: values.slice(start, start + limit), page, totalPages, hasNextPage: page < totalPages};
}
function slugify(value: string): string { return value.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, ""); }
function corsHeaders(origin: string | null, configured: string): HeadersInit { const allowed = configured.split(",").map((item) => item.trim()).filter(Boolean); return origin && allowed.includes(origin) ? {"Access-Control-Allow-Origin": origin, "Access-Control-Allow-Methods": "GET,OPTIONS", "Access-Control-Allow-Headers": "Accept", Vary: "Origin"} : {}; }
function json(value: unknown, cors: HeadersInit, maxAge: number): Response { return Response.json(value, {headers: {...cors, "Cache-Control": `public, max-age=${maxAge}`}}); }
function jsonError(status: number, code: string, message: string, cors: HeadersInit): Response { return Response.json({error: {code, message}}, {status, headers: cors}); }
function required(value: string | null, name: string, min: number, max: number): string { const result = value?.trim() ?? ""; if (result.length < min || result.length > max) throw new InputError(`${name} is invalid.`); return result; }
function intParam(url: URL, name: string, min: number, max: number, fallback: number): number { const raw = url.searchParams.get(name); if (raw == null) return fallback; const value = Number(raw); if (!Number.isInteger(value) || value < min || value > max) throw new InputError(`${name} is invalid.`); return value; }
function record(value: unknown): Json { if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Expected object"); return value as Json; }
function array(value: unknown): unknown[] { return Array.isArray(value) ? value : []; }
function requiredText(value: unknown, max = 500): string { const result = typeof value === "string" ? value.trim().slice(0, max) : ""; if (!result) throw new Error("Missing required text"); return result; }