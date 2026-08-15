# Online Quote Discovery Design

## Goal

Add internet-backed Quote discovery while preserving manual Quote creation, local-first node storage, autosave, and offline readability.

## User Experience

Expanded Quote editor has two modes:

- **Discover**: browse popular authors, search authors, browse paginated quotes, and select a quote.
- **Write manually**: use existing body, author, source, collection, tags, favorite, and copy controls.

Discover is the default only when the current Quote node still contains the untouched default template. Existing or manually edited Quote nodes open in Write manually mode so network access never blocks editing.

Selecting an internet quote:

- replaces node body with quote text;
- sets structured author;
- sets source label to the provider attribution;
- stores provider source URL;
- stores provider tags;
- keeps collection and favorite unchanged;
- triggers the existing inline autosave pipeline;
- switches to Write manually so the selected snapshot can be reviewed or edited.

## Flutter Architecture

Add a small quote discovery boundary under `lib/features/mindmap/`:

- `domain/quote_catalog.dart`: immutable author, quote, page, error, and repository contracts; pure Dart.
- `data/firebase_quote_catalog.dart`: Firebase callable adapter and strict response parsing.
- `application/quote_catalog_providers.dart`: Riverpod client/repository providers with test overrides.
- `presentation/node_editors/quote_discovery_panel.dart`: author search, popular authors, quote list, pagination, loading/error/empty states.

`knowledge_node_editors.dart` composes the panel with the existing manual editor. It does not perform HTTP or Firebase calls directly.

Add `cloud_functions` to Flutter dependencies. Firebase is available only on Web, Android, iOS, and macOS in this app, so Windows and Linux use a disabled catalog repository and keep manual mode fully functional.

## Firebase Functions Architecture

Create a TypeScript Functions workspace in `functions/` using Firebase Functions v2 callable functions.

Export:

- `getPopularQuoteAuthors`
- `searchQuoteAuthors`
- `listQuotesByAuthor`

Each function:

- validates callable input before upstream requests;
- limits query length, page number, and page size;
- applies a fixed upstream timeout;
- maps upstream failures to stable Firebase `HttpsError` codes;
- returns only the documented response contract;
- never returns raw upstream errors or headers;
- uses a provider adapter so the upstream can be replaced without changing Flutter;
- sends short public cache headers where callable infrastructure permits;
- uses in-memory cache only as an optimization, never as required state.

Default upstream is Quotable-compatible and configured by `QUOTE_API_BASE_URL`. No provider secret is embedded in Flutter. A later provider requiring credentials must use Firebase Secret Manager.

## Callable Contracts

### `getPopularQuoteAuthors`

Input:

```json
{}
```

Output:

```json
{
  "authors": [
    {
      "id": "author-id",
      "name": "Author Name",
      "slug": "author-slug",
      "description": "Short biography",
      "quoteCount": 12
    }
  ]
}
```

The backend returns a curated popular-author list enriched from the provider. Missing provider authors are omitted, not treated as total failure.

### `searchQuoteAuthors`

Input:

```json
{
  "query": "maya",
  "page": 1,
  "limit": 20
}
```

Output includes `authors`, `page`, `totalPages`, and `hasNextPage`.

Rules:

- trimmed query must contain 2-80 characters;
- page is 1-1000;
- limit is 1-30.

### `listQuotesByAuthor`

Input:

```json
{
  "authorSlug": "maya-angelou",
  "page": 1,
  "limit": 20
}
```

Output:

```json
{
  "quotes": [
    {
      "id": "quote-id",
      "text": "Quote text",
      "authorName": "Author Name",
      "authorSlug": "author-slug",
      "tags": ["wisdom"],
      "sourceUrl": "https://provider.example/quotes/quote-id",
      "provider": "quotable"
    }
  ],
  "page": 1,
  "totalPages": 3,
  "hasNextPage": true
}
```

## Node Data

Extend `QuotePayload` additively with:

- `remoteQuoteId`
- `quoteProvider`
- `sourceUrl`

Existing `author`, `quoteSource`, `collection`, `tags`, and `isFavorite` remain unchanged. Internet quote text stays in node body, making the node fully readable offline. Manual edits preserve remote attribution unless the user explicitly clears the selected internet source.

## States and Errors

Discover panel supports:

- initial popular authors;
- debounced author search after 2 characters;
- author selected;
- quote page loading;
- quote page loaded;
- empty authors;
- empty quotes;
- retryable network/provider error;
- unsupported platform.

Errors never replace manual controls. A visible **Write manually** action remains available in every state.

## Security and Reliability

- No provider token ships in Flutter.
- Callable functions validate all untrusted input.
- Upstream URLs are server-configured, not supplied by clients.
- Responses have bounded list and string sizes.
- Functions use timeout and stable error mapping.
- Flutter parsing rejects malformed callable responses with a user-safe catalog error.
- Local Quote saving does not depend on function availability.

## Testing

Flutter tests cover:

- domain response parsing and malformed-response rejection;
- repository callable request mapping;
- popular authors, search, loading, empty, error, retry, pagination, and unsupported-platform UI;
- selecting a quote updates body and structured payload through autosave;
- manual mode works without Firebase;
- existing Quote tests remain green.

Functions tests cover:

- input validation;
- provider request mapping;
- response normalization;
- timeout and upstream error mapping;
- popular-author partial failures;
- result-size bounds.

## Deployment

Required setup:

1. Initialize Firebase Functions TypeScript workspace.
2. Set `QUOTE_API_BASE_URL` in Functions environment configuration.
3. Deploy functions.
4. Add `cloud_functions` Flutter dependency.
5. Run Flutter with the existing Firebase project configuration.

Functions emulator support is included for local development. Production app falls back to manual mode if callable functions are unavailable.

## Deliberate Limits

No infinite scrolling, bulk-import, random feed, social sharing, provider account, quote verification, or background synchronization. Add only after usage proves need.