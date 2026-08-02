# Cloudflare Quote Discovery Migration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Firebase callable Quote discovery with a free Cloudflare Worker and HTTP Flutter adapter.

**Architecture:** Keep catalog domain and UI unchanged. Runtime config supplies an optional Worker base URL. Riverpod constructs an injected `http.Client` repository or disabled fallback. Worker exposes bounded read-only JSON GET routes.

**Tech Stack:** Flutter, Dart, Riverpod, `http`, Cloudflare Workers, TypeScript, Node test runner.

---

### Task 1: Runtime and HTTP adapter

**Files:**
- Modify: `lib/core/config/runtime_config.dart`
- Replace: `lib/features/mindmap/data/firebase_quote_catalog.dart` with `http_quote_catalog.dart`
- Modify: `lib/features/mindmap/application/quote_catalog_providers.dart`
- Modify: `pubspec.yaml`
- Test: runtime and HTTP adapter tests

- [ ] Add `VAR_QUOTE_ENDPOINT` parsing.
- [ ] Implement strict HTTP GET repository with timeout and error mapping.
- [ ] Inject and dispose `http.Client` through Riverpod.
- [ ] Remove `cloud_functions` dependency and callable code.

### Task 2: Cloudflare Worker

**Files:**
- Create: `workers/quote-catalog/package.json`
- Create: `workers/quote-catalog/wrangler.jsonc`
- Create: `workers/quote-catalog/tsconfig.json`
- Create: `workers/quote-catalog/src/index.ts`
- Create: `workers/quote-catalog/test/index.test.ts`

- [ ] Implement health, popular authors, author search, and quote routes.
- [ ] Add validation, timeout, normalization, cache headers, and CORS.
- [ ] Add Node tests and TypeScript build.

### Task 3: Remove Firebase Quote backend

**Files:**
- Modify: `firebase.json`
- Remove: generated `functions/` Quote backend workspace

- [ ] Remove only Quote Functions configuration and generated workspace.
- [ ] Preserve Firestore, Storage, Hosting, and unrelated Firebase settings.

### Task 4: Validation

- [ ] Run formatting and focused Flutter tests.
- [ ] Run Worker tests and TypeScript checks.
- [ ] Run Flutter analyzer on modified files.
- [ ] Verify manual mode works without endpoint.