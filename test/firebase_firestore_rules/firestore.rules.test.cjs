const { readFileSync } = require('node:fs');
const { after, before, beforeEach, test } = require('node:test');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp, writeBatch } = require('firebase/firestore');

let env;
const room = '123e4567-e89b-42d3-a456-426614174000';
const auth = (uid, role, email = `${uid}@example.com`) => env.authenticatedContext(uid, { email, email_verified: true, firebase: { sign_in_provider: 'password' }, role }).firestore();

before(async () => {
  env = await initializeTestEnvironment({ projectId: 'var-rules-test', firestore: { rules: readFileSync('../../firestore.rules', 'utf8') } });
});
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

async function seed() {
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, 'rooms', room), { schemaVersion: 2, ownerUid: 'owner', dayKey: '2026-07-28', createdAt: new Date() });
    for (const [uid, role] of [['owner', 'owner'], ['editor', 'editor'], ['commenter', 'commenter'], ['viewer', 'viewer']]) await setDoc(doc(db, 'rooms', room, 'members', uid), { uid, email: `${uid}@example.com`, displayName: uid, role, joinedAt: new Date() });
    await setDoc(doc(db, 'rooms', room, 'nodes', 'node'), nodeData('owner'));
  });
}

const nodeData = (uid, revision = 1, deleted = false) => ({ schemaVersion: 1, remoteNodeId: 'node', dayKey: '2026-07-28', revision, deleted, payload: deleted ? null : { id: 'node', day: '2026-07-28', title: 'Node' }, createdByUid: 'owner', updatedByUid: uid, updatedAt: serverTimestamp() });
const nodeDataV2 = (uid, revision = 1, mutationId = `mutation-${revision}`) => ({ ...nodeData(uid, revision), schemaVersion: 2, lastMutationId: mutationId });
const commentData = uid => ({ id: 'comment', nodeId: 'node', roomId: room, authorUid: uid, authorDisplayName: uid, body: 'ok', createdAt: serverTimestamp() });

test('user backup owner allowed and cross denied', async () => {
  await assertSucceeds(setDoc(doc(auth('owner'), 'users', 'owner', 'nodes', 'one'), { value: 1 }));
  await assertFails(setDoc(doc(auth('stranger'), 'users', 'owner', 'nodes', 'two'), { value: 1 }));
});

test('room create requires verified non-anonymous owner', async () => {
  const data = { schemaVersion: 2, ownerUid: 'owner', dayKey: '2026-07-28', createdAt: serverTimestamp() };
  const ownerDb = auth('owner');
  const batch = writeBatch(ownerDb);
  batch.set(doc(ownerDb, 'rooms', room), data);
  batch.set(doc(ownerDb, 'rooms', room, 'members', 'owner'), { uid: 'owner', email: 'owner@example.com', displayName: 'Owner', role: 'owner', joinedAt: serverTimestamp() });
  await assertSucceeds(batch.commit());
  const anonymous = env.authenticatedContext('anon', { email_verified: true, firebase: { sign_in_provider: 'anonymous' } }).firestore();
  const unverified = env.authenticatedContext('unverified', { email_verified: false, firebase: { sign_in_provider: 'password' } }).firestore();
  await assertFails(setDoc(doc(anonymous, 'rooms', `${room}1`), { ...data, ownerUid: 'anon' }));
  await assertFails(setDoc(doc(unverified, 'rooms', `${room}2`), { ...data, ownerUid: 'unverified' }));
});

test('room read allows members only', async () => {
  await seed();
  await assertSucceeds(getDoc(doc(auth('owner'), 'rooms', room)));
  await assertSucceeds(getDoc(doc(auth('viewer'), 'rooms', room)));
  await assertFails(getDoc(doc(auth('stranger'), 'rooms', room)));
});

test('node roles, revisions, tombstones, and identity constraints', async () => {
  await seed();
  await assertSucceeds(setDoc(doc(auth('owner'), 'rooms', room, 'nodes', 'node'), nodeData('owner', 2)));
  await assertSucceeds(setDoc(doc(auth('editor'), 'rooms', room, 'nodes', 'node'), nodeData('editor', 3, true)));
  await assertFails(setDoc(doc(auth('editor'), 'rooms', room, 'nodes', 'node'), nodeData('editor', 5)));
  await assertFails(setDoc(doc(auth('commenter'), 'rooms', room, 'nodes', 'node'), nodeData('commenter', 4)));
  await assertFails(setDoc(doc(auth('viewer'), 'rooms', room, 'nodes', 'node'), nodeData('viewer', 4)));
  await assertFails(setDoc(doc(auth('editor'), 'rooms', room, 'nodes', 'wrong'), nodeData('editor', 4)));
  await assertFails(setDoc(doc(auth('editor'), 'rooms', room, 'nodes', 'node'), { ...nodeData('editor', 4), dayKey: '2026-07-29' }));
  await assertFails(deleteDoc(doc(auth('owner'), 'rooms', room, 'nodes', 'node')));
});

test('node schema v1 and v2 remain rollout compatible', async () => {
  await seed();
  await assertSucceeds(setDoc(doc(auth('editor'), 'rooms', room, 'nodes', 'node'), nodeDataV2('editor', 2)));
  await assertSucceeds(setDoc(doc(auth('editor'), 'rooms', room, 'nodes', 'node'), nodeDataV2('editor', 3, 'next-mutation')));
  await assertSucceeds(setDoc(doc(auth('editor'), 'rooms', room, 'nodes', 'node'), nodeData('editor', 4)));
  await assertFails(setDoc(doc(auth('editor'), 'rooms', room, 'nodes', 'node'), nodeDataV2('editor', 5, '')));
  await assertFails(setDoc(doc(auth('editor'), 'rooms', room, 'nodes', 'node'), { ...nodeData('editor', 5), lastMutationId: 'unexpected' }));
  await assertFails(setDoc(doc(auth('editor'), 'rooms', room, 'nodes', 'node'), { ...nodeDataV2('editor', 5), schemaVersion: 3 }));
});

test('comment roles, immutable data, and forged identity', async () => {
  await seed();
  for (const uid of ['owner', 'editor', 'commenter']) await assertSucceeds(setDoc(doc(auth(uid), 'rooms', room, 'nodes', 'node', 'comments', `${uid}`), { ...commentData(uid), id: uid }));
  await assertFails(setDoc(doc(auth('viewer'), 'rooms', room, 'nodes', 'node', 'comments', 'viewer'), { ...commentData('viewer'), id: 'viewer' }));
  await assertFails(setDoc(doc(auth('commenter'), 'rooms', room, 'nodes', 'node', 'comments', 'forged'), { ...commentData('other'), id: 'forged' }));
  await assertFails(setDoc(doc(auth('commenter'), 'rooms', room, 'nodes', 'missing', 'comments', 'missing'), { ...commentData('commenter'), id: 'missing', nodeId: 'missing' }));
  const ref = doc(auth('owner'), 'rooms', room, 'nodes', 'node', 'comments', 'owner');
  await assertFails(updateDoc(ref, { body: 'changed' }));
  await assertFails(deleteDoc(ref));
});

test('owner cannot create another owner or mismatched member', async () => {
  await seed();
  const member = { email: 'member@example.com', displayName: 'Member', joinedAt: serverTimestamp() };
  await assertFails(setDoc(doc(auth('owner'), 'rooms', room, 'members', 'second-owner'), { ...member, uid: 'second-owner', role: 'owner' }));
  await assertFails(setDoc(doc(auth('owner'), 'rooms', room, 'members', 'member'), { ...member, uid: 'other', role: 'viewer' }));
  await assertFails(setDoc(doc(auth('owner'), 'rooms', room, 'members', 'member'), { ...member, uid: 'member', role: 'viewer' }));
});

test('invite recipient can exact get but cannot list', async () => {
  await seed();
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'rooms', room, 'invites', 'invite'), inviteData());
  });
  const recipient = auth('member', undefined, 'member@example.com');
  await assertSucceeds(getDoc(doc(recipient, 'rooms', room, 'invites', 'invite')));
  await assertFails(getDoc(doc(auth('other'), 'rooms', room, 'invites', 'invite')));
});

test('invite redemption is atomic, email-bound, unexpired, and single-use', async () => {
  await seed();
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'rooms', room, 'invites', 'invite'), inviteData());
    await setDoc(doc(context.firestore(), 'rooms', room, 'invites', 'expired'), inviteData({ inviteId: 'expired', expiresAt: new Date(Date.now() - 1000) }));
  });
  const redeem = async (db, inviteId = 'invite') => {
    const batch = writeBatch(db);
    batch.update(doc(db, 'rooms', room, 'invites', inviteId), { status: 'redeemed', redeemedByUid: 'member', redeemedAt: serverTimestamp() });
    batch.set(doc(db, 'rooms', room, 'members', 'member'), { uid: 'member', email: 'member@example.com', displayName: 'Member', role: 'editor', joinedAt: serverTimestamp(), inviteId });
    return batch.commit();
  };
  await assertFails(redeem(auth('member', undefined, 'wrong@example.com')));
  await assertFails(redeem(auth('member'), 'expired'));
  await assertSucceeds(redeem(auth('member')));
  await assertFails(redeem(auth('member')));
});

test('member role changes and removal are owner-only and owner immutable', async () => {
  await seed();
  await assertSucceeds(updateDoc(doc(auth('owner'), 'rooms', room, 'members', 'editor'), { role: 'viewer' }));
  await assertFails(updateDoc(doc(auth('editor'), 'rooms', room, 'members', 'viewer'), { role: 'editor' }));
  await assertFails(updateDoc(doc(auth('owner'), 'rooms', room, 'members', 'owner'), { role: 'viewer' }));
  await assertFails(deleteDoc(doc(auth('owner'), 'rooms', room, 'members', 'owner')));
  await assertSucceeds(deleteDoc(doc(auth('owner'), 'rooms', room, 'members', 'viewer')));
});

test('unknown room path denied', async () => {
  await seed();
  await assertFails(setDoc(doc(auth('owner'), 'rooms', room, 'unknown', 'one'), { value: 1 }));
});

async function seedProjectRoom() {
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, 'rooms', room), { schemaVersion: 3, ownerUid: 'owner', targetKind: 'projectBoard', targetId: 'board', targetLabel: 'Board', createdAt: new Date() });
    for (const [uid, role] of [['owner', 'owner'], ['editor', 'editor'], ['commenter', 'commenter'], ['viewer', 'viewer']]) await setDoc(doc(db, 'rooms', room, 'members', uid), { uid, email: `${uid}@example.com`, displayName: uid, role, joinedAt: new Date() });
  });
}

const votingSession = (overrides = {}) => ({ sessionId: 'session-1', ballotStorageVersion: 1, status: 'active', isAnonymous: true, resultsRevealed: false, maxVotesPerParticipant: 3, ...overrides });
const boardPayload = (title = 'Board', session = votingSession()) => ({ id: 'board', kind: 'project', title, votingSession: session, updatedAt: '2026-07-28T00:00:00.000Z' });
const boardEnvelope = (uid, revision = 1, payload = boardPayload()) => ({ schemaVersion: 1, boardId: 'board', revision, payload, createdByUid: 'owner', updatedByUid: uid, lastMutationId: `mutation-${uid}-${revision}`, updatedAt: serverTimestamp() });

test('project room bootstrap atomically requires matching owner board', async () => {
  const projectRoom = `${room}9`;
  const ownerDb = auth('owner');
  const bootstrap = async (overrides = {}) => {
    const batch = writeBatch(ownerDb);
    batch.set(doc(ownerDb, 'rooms', projectRoom), {
      schemaVersion: 3,
      ownerUid: 'owner',
      targetKind: 'projectBoard',
      targetId: 'board',
      targetLabel: 'Board',
      createdAt: serverTimestamp(),
      ...overrides.room,
    });
    batch.set(doc(ownerDb, 'rooms', projectRoom, 'members', 'owner'), {
      uid: 'owner',
      email: 'owner@example.com',
      displayName: 'Owner',
      role: 'owner',
      joinedAt: serverTimestamp(),
    });
    batch.set(doc(ownerDb, 'rooms', projectRoom, 'boards', 'board'), {
      ...boardEnvelope('owner'),
      ...overrides.board,
    });
    return batch.commit();
  };
  await assertSucceeds(bootstrap());
  await env.clearFirestore();
  await assertFails(bootstrap({ room: { targetId: 'other' } }));
  await env.clearFirestore();
  await assertFails(bootstrap({ board: { updatedByUid: 'editor' } }));

  const withoutBoardRoom = `${room}8`;
  const withoutBoard = writeBatch(ownerDb);
  withoutBoard.set(doc(ownerDb, 'rooms', withoutBoardRoom), {
    schemaVersion: 3,
    ownerUid: 'owner',
    targetKind: 'projectBoard',
    targetId: 'board',
    targetLabel: 'Board',
    createdAt: serverTimestamp(),
  });
  withoutBoard.set(doc(ownerDb, 'rooms', withoutBoardRoom, 'members', 'owner'), {
    uid: 'owner',
    email: 'owner@example.com',
    displayName: 'Owner',
    role: 'owner',
    joinedAt: serverTimestamp(),
  });
  await assertFails(withoutBoard.commit());
});

test('project ballots enforce owner, session, role, and vote limit', async () => {
  await seedProjectRoom();
  const board = doc(auth('owner'), 'rooms', room, 'boards', 'board');
  await assertSucceeds(setDoc(board, boardEnvelope('owner')));
  const ballot = (uid, objectIds = ['object'], sessionId = 'session-1') => ({ schemaVersion: 1, ownerUid: uid, sessionId, objectIds, updatedAt: serverTimestamp() });
  await assertSucceeds(setDoc(doc(auth('commenter'), 'rooms', room, 'boards', 'board', 'ballots', 'commenter'), ballot('commenter')));
  await assertFails(setDoc(doc(auth('commenter'), 'rooms', room, 'boards', 'board', 'ballots', 'owner'), ballot('owner')));
  await assertFails(setDoc(doc(auth('viewer'), 'rooms', room, 'boards', 'board', 'ballots', 'viewer'), ballot('viewer')));
  await assertFails(setDoc(doc(auth('commenter'), 'rooms', room, 'boards', 'board', 'ballots', 'commenter'), ballot('commenter', ['one'], 'old-session')));
  await assertFails(setDoc(doc(auth('commenter'), 'rooms', room, 'boards', 'board', 'ballots', 'commenter'), ballot('commenter', ['one', 'two', 'three', 'four'])));
  await assertFails(getDoc(doc(auth('owner'), 'rooms', room, 'boards', 'board', 'ballots', 'commenter')));
  await assertSucceeds(getDoc(doc(auth('commenter'), 'rooms', room, 'boards', 'board', 'ballots', 'commenter')));
  await assertFails(setDoc(doc(auth('commenter'), 'rooms', room, 'boards', 'board'), boardEnvelope('commenter', 2)));
  await assertFails(setDoc(doc(auth('editor'), 'rooms', room, 'boards', 'board'), boardEnvelope('editor', 2, boardPayload('Bad', { ...votingSession(), allocations: { editor: ['object'] } }))));
  await assertSucceeds(setDoc(doc(auth('editor'), 'rooms', room, 'boards', 'board'), boardEnvelope('editor', 2, boardPayload('Lifecycle', votingSession({ status: 'ended', resultsRevealed: true })))));
});

test('presence enforces owner, schema, types, timestamp, and paired cursor', async () => {
  await seedProjectRoom();
  const ref = doc(auth('editor'), 'rooms', room, 'presence', 'editor');
  const valid = { name: 'Editor', color: 4294967295, cursorX: 12.5, cursorY: -4, selectedNodeId: null, isEditing: false, lastActive: serverTimestamp() };
  await assertSucceeds(setDoc(ref, valid));
  await assertSucceeds(setDoc(ref, { ...valid, cursorX: 20, cursorY: 30, selectedNodeId: 'node', isEditing: true }));
  await assertSucceeds(deleteDoc(ref));
  await assertFails(setDoc(doc(auth('editor'), 'rooms', room, 'presence', 'owner'), valid));
  await assertFails(setDoc(ref, { ...valid, extra: true }));
  const { cursorY, ...missingCursorY } = valid;
  await assertFails(setDoc(ref, missingCursorY));
  await assertFails(setDoc(ref, { ...valid, color: 'blue' }));
  await assertFails(setDoc(ref, { ...valid, lastActive: new Date(0) }));
});

test('project reactions and comments enforce role and identity', async () => {
  await seedProjectRoom();
  const reaction = uid => ({ fromId: uid, emoji: '👍', t: 1000, expiresAt: 6000 });
  await assertSucceeds(setDoc(doc(auth('commenter'), 'rooms', room, 'reactions', 'one'), reaction('commenter')));
  await assertFails(setDoc(doc(auth('viewer'), 'rooms', room, 'reactions', 'two'), reaction('viewer')));
  await assertFails(setDoc(doc(auth('commenter'), 'rooms', room, 'reactions', 'three'), reaction('owner')));
  const comment = uid => ({ id: uid, objectId: 'object', body: 'Useful note', authorName: uid, authorUid: uid, createdAt: serverTimestamp(), parentId: null, isResolved: false, resolvedByUid: null });
  await assertSucceeds(setDoc(doc(auth('commenter'), 'rooms', room, 'boardComments', 'commenter'), comment('commenter')));
  await assertFails(setDoc(doc(auth('viewer'), 'rooms', room, 'boardComments', 'viewer'), comment('viewer')));
  await assertFails(setDoc(doc(auth('commenter'), 'rooms', room, 'boardComments', 'forged'), { ...comment('owner'), id: 'forged' }));
  await assertSucceeds(updateDoc(doc(auth('editor'), 'rooms', room, 'boardComments', 'commenter'), { isResolved: true, resolvedByUid: 'editor' }));
  await assertFails(updateDoc(doc(auth('commenter'), 'rooms', room, 'boardComments', 'commenter'), { body: 'Changed' }));
});

function inviteData(overrides = {}) {
  return { inviteId: 'invite', roomId: room, email: 'member@example.com', role: 'editor', status: 'active', createdAt: new Date(), expiresAt: new Date(Date.now() + 86400000), createdByUid: 'owner', ...overrides };
}
