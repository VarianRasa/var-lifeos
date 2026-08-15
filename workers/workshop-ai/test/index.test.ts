import assert from 'node:assert/strict';
import test from 'node:test';

import {handleRequest, type AiRunner} from '../src/index.ts';

const result = {
  summary: 'Team chose weekly releases.',
  themes: [{name: 'Delivery', sourceIds: ['s1']}],
  clusters: [{name: 'Cadence', sourceIds: ['s1', 's2']}],
  decisions: [{text: 'Release weekly', sourceIds: ['s1']}],
  actionItems: [{text: 'Prepare release', sourceIds: ['s2']}],
  risks: [{text: 'Limited capacity', sourceIds: ['s2']}],
};

function ai(response: unknown = {response: result}): AiRunner {
  return {run: async () => response};
}

function request(body: unknown): Request {
  return new Request('https://worker.test/analyze', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify(body),
  });
}

test('returns typed workshop analysis and model metadata', async () => {
  const response = await handleRequest(request({
    sticky: [
      {id: 's1', text: 'Ship weekly', votes: 3, locale: 'en'},
      {id: 's2', text: 'Capacity is tight', votes: 1, locale: 'en'},
    ],
  }), ai());
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    ...result,
    model: '@cf/meta/llama-3.1-8b-instruct-fast',
    version: '1',
  });
});

test('rejects more than 300 sticky notes', async () => {
  const response = await handleRequest(request({
    sticky: Array.from({length: 301}, (_, index) => ({
      id: `s${index}`,
      text: 'Text',
      votes: 0,
      locale: 'id',
    })),
  }), ai());
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), {
    error: {code: 'invalid-input', message: 'sticky must contain 1 to 300 items.'},
  });
});

test('rejects unknown sticky fields', async () => {
  const response = await handleRequest(request({
    sticky: [{id: 's1', text: 'Text', votes: 0, locale: 'id', secret: 'no'}],
  }), ai());
  assert.equal(response.status, 400);
  assert.match(JSON.stringify(await response.json()), /only id, text, votes, locale/);
});

test('rejects model source IDs absent from input', async () => {
  const invalid = structuredClone(result);
  invalid.themes[0].sourceIds = ['missing'];
  const response = await handleRequest(request({
    sticky: [{id: 's1', text: 'Text', votes: 0, locale: 'id'}],
  }), ai({response: invalid}));
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), {
    error: {code: 'invalid-model-response', message: 'Model returned invalid structured output.'},
  });
});
