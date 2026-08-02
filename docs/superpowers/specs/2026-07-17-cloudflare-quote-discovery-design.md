# Cloudflare Quote Discovery Design

## Goal

Provide internet-backed Quote discovery without Firebase Blaze billing. Use Cloudflare Workers Free as a small public proxy while preserving manual Quote editing and offline local snapshots.

## Architecture Change

Remove the Firebase callable integration created for Quote discovery:

- remove Flutter `cloud_functions` dependency;
- remove `FirebaseQuoteCatalog` and callable client providers;
- remove Firebase Functions configuration and Quote Functions workspace from the active architecture;
- keep unrelated Firebase configuration unchanged.

Replace it with:

- a Cloudflare Worker under `workers/quote-catalog/`;
- a Flutter HTTP repository using the already-installed `http` package;
- runtime configuration through `VAR_QUOTE_ENDPOINT`;
- a disabled repository when no endpoint is configured.

The existing domain models and Quote discovery UI remain provider-independent.

## Worker API

The Worker exposes JSON endpoints:

- `GET /authors/popular`
- `GET /authors/search?q=maya&page=1&limit=20`
- `GET /quotes?author=maya-angelou&page=1&limit=20`
- `GET /health`

Responses keep the same author and quote contracts already used by Flutter.

## Worker Behavior

- validates query strings and bounds page/limit;
- uses an environment variable `QUOTE_API_BASE_URL`;
- defaults to a Quotable-compatible upstream;
- applies an 8-second upstream timeout;
- normalizes responses and strips unknown fields;
- returns stable JSON errors;
- sets CORS only for configured `ALLOWED_ORIGINS`;
- supports local Flutter development origins;
- caches popular authors and quote pages with Cloudflare Cache API;
- applies short cache TTL values;
- never accepts arbitrary upstream URLs from clients.

No API secret is needed for the default provider. Provider secrets, if needed later, use Wrangler secrets.

## Flutter Runtime Configuration

Extend `RuntimeConfig` with:

- `quoteEndpoint: Uri?`
- `quoteDiscoveryEnabled`

Read from:

```text
--dart-define=VAR_QUOTE_ENDPOINT=https://var-quote-catalog.<account>.workers.dev
```

If absent, the Discover panel shows an unavailable message and **Write manually** remains fully functional.

## HTTP Repository

Create `HttpQuoteCatalog` with an injected `http.Client`.

Responsibilities:

- build only relative paths against configured endpoint;
- apply client-side timeout;
- require HTTP 200 responses;
- parse JSON maps strictly through existing domain parsers;
- map timeout, malformed JSON, non-200 responses, and network failures into `QuoteCatalogException`;
- close the HTTP client through Riverpod disposal.

## UI

Existing Discover/Write manually interface remains unchanged.

Discover supports:

- popular authors;
- debounced author search;
- author quote list;
- pagination;
- retry, loading, empty, and unavailable states;
- selecting a quote into local body and structured attribution.

## Deployment

Worker project contains:

- `wrangler.jsonc`
- `package.json`
- `tsconfig.json`
- `src/index.ts`
- Node tests

Deployment commands:

```bash
cd workers/quote-catalog
npm install
npm test
npx wrangler deploy
```

After deployment, run Flutter with `VAR_QUOTE_ENDPOINT`.

## Security and Cost Controls

- no Firebase billing dependency;
- bounded public inputs and outputs;
- strict CORS allowlist;
- cached GET responses;
- no write endpoints;
- no user data sent to Worker;
- Worker free-tier limits naturally cap service usage;
- manual mode remains available when limits or upstream availability fail.

## Testing

Flutter tests cover:

- runtime flag parsing;
- HTTP paths and query parameters;
- response parsing;
- timeout/network/non-200/malformed JSON handling;
- disabled endpoint fallback;
- existing discovery selection flow.

Worker tests cover:

- routing;
- CORS;
- input validation;
- upstream mapping;
- timeout and stable errors;
- cacheable headers.

## Deliberate Limits

No Firebase Functions fallback, infinite scrolling, bulk import, random feed, provider accounts, quote verification, or analytics collection.