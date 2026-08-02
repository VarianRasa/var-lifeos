import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { testing } from '../src/index.ts';

type Value = { arrayValue?: { values?: Value[] }; booleanValue?: boolean; integerValue?: string; mapValue?: { fields?: Record<string, Value> }; stringValue?: string };
const string = (value: string): Value => ({ stringValue: value });
const integer = (value: number): Value => ({ integerValue: String(value) });
const map = (fields: Record<string, Value>): Value => ({ mapValue: { fields } });

test('validates path-bound ballot and authoritative limits', () => {
  const ballot = { roomId: 'r1', boardId: 'b1', sessionId: 's1', mutationId: 'm1', choices: ['b', 'a'] };
  assert.deepEqual(testing.parseBallot(ballot, 'r1', 'b1', 's1', ['a', 'b'], 2), { mutationId: 'm1', choices: ['a', 'b'] });
  assert.throws(() => testing.parseBallot({ ...ballot, roomId: 'other' }, 'r1', 'b1', 's1', ['a', 'b'], 2));
  assert.throws(() => testing.parseBallot({ ...ballot, choices: ['a', 'a'] }, 'r1', 'b1', 's1', ['a'], 2));
  assert.throws(() => testing.parseBallot(ballot, 'r1', 'b1', 's1', ['a', 'b'], 1));
});

test('requires active known Firestore membership role', () => {
  assert.equal(testing.parseMember({ role: string('viewer') }), 'viewer');
  assert.throws(() => testing.parseMember({ role: string('viewer'), active: { booleanValue: false } }));
  assert.throws(() => testing.parseMember({ role: string('admin') }));
  assert.throws(() => testing.parseMember({}));
});

test('board metadata binds active session, max votes, and options', () => {
  const fields = {
    payload: map({
      votingSession: map({ status: string('active'), sessionId: string('s1'), maxVotesPerParticipant: integer(2) }),
      objects: { arrayValue: { values: [map({ id: string('a') }), map({ id: string('b') })] } },
    }),
  };
  assert.deepEqual(testing.parseBoardAuthority(fields, 's1'), { maxVotes: 2, options: ['a', 'b'] });
  assert.throws(() => testing.parseBoardAuthority(fields, 'other'));
  assert.throws(() => testing.parseBoardAuthority({ payload: map({ votingSession: map({ status: string('ended'), sessionId: string('s1'), maxVotesPerParticipant: integer(2) }) }) }, 's1'));
});

test('mutation transaction serializes concurrent retries and gates every write', async () => {
  const source = await readFile(new URL('../src/index.ts', import.meta.url), 'utf8');
  const batch = source.slice(source.indexOf('await env.DB.batch(['), source.indexOf(']);', source.indexOf('await env.DB.batch([')));
  assert.match(batch, /INSERT OR IGNORE INTO processed_mutations/);
  assert.equal((batch.match(/applied=0/g) ?? []).length, 3);
  assert.match(batch, /UPDATE vote_totals/);
  assert.match(batch, /INSERT INTO private_ballots/);
  assert.match(batch, /UPDATE processed_mutations SET applied=1/);
});

test('removes membership grants and keeps private ballots out of reads and logs', async () => {
  const source = await readFile(new URL('../src/index.ts', import.meta.url), 'utf8');
  const aggregate = source.slice(source.indexOf("resource === 'aggregate'"), source.indexOf("resource === 'receipt'"));
  const receipt = source.slice(source.indexOf("resource === 'receipt'"), source.indexOf("return json({ error: 'method not allowed'"));
  assert.doesNotMatch(source, /Membership-Grant|MEMBERSHIP_GRANT|HMAC/);
  assert.doesNotMatch(aggregate, /private_ballots|uid|choices_json/);
  assert.doesNotMatch(receipt, /private_ballots|choices_json/);
  assert.doesNotMatch(source, /console\.(log|warn).*ballot|console\.(log|warn).*uid/i);
});
