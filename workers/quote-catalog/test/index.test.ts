import test from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";

test("health route returns cacheable JSON", async () => {
  const response = await worker.fetch(new Request("https://worker.test/health"), {});
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Cache-Control"), "public, max-age=60");
  assert.deepEqual(await response.json(), {ok: true});
});

test("search validates short query without upstream call", async () => {
  const response = await worker.fetch(new Request("https://worker.test/authors/search?q=x"), {});
  assert.equal(response.status, 400);
});

test("CORS allows only configured origins", async () => {
  const response = await worker.fetch(
    new Request("https://worker.test/health", {headers: {Origin: "https://app.example"}}),
    {ALLOWED_ORIGINS: "https://app.example"},
  );
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), "https://app.example");
});