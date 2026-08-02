const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { after, before, beforeEach, describe, test } = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  deleteObject,
  getBytes,
  ref,
  updateMetadata,
  uploadBytes,
} = require('firebase/storage');

const projectId = 'demo-var-app';
const ownerId = 'owner-user';
const otherUserId = 'other-user';
const attachmentId = '123e4567-e89b-12d3-a456-426614174000';
const attachmentPath = `attachments/${ownerId}/${attachmentId}`;
const validMetadata = {
  contentType: 'image/png',
  customMetadata: { attachmentId, schemaVersion: '1' },
};

let testEnvironment;

function storageFor(context) {
  return context.storage(`gs://${projectId}.appspot.com`);
}

function attachmentRef(context, objectPath = attachmentPath) {
  return ref(storageFor(context), objectPath);
}

async function seedOwnerAttachment() {
  const owner = testEnvironment.authenticatedContext(ownerId);
  await assertSucceeds(
    uploadBytes(
      attachmentRef(owner),
      Uint8Array.from([137, 80, 78, 71]),
      validMetadata,
    ),
  );
}

before(async () => {
  const rules = fs.readFileSync(
    path.resolve(__dirname, '..', '..', 'storage.rules'),
    'utf8',
  );
  testEnvironment = await initializeTestEnvironment({
    projectId,
    storage: { rules },
  });
});

beforeEach(async () => {
  await testEnvironment.clearStorage();
});

after(async () => {
  await testEnvironment.cleanup();
});

describe('Firebase Storage attachment rules', () => {
  test('deny unauthenticated create and read', async () => {
    const unauthenticated = testEnvironment.unauthenticatedContext();
    await assertFails(
      uploadBytes(
        attachmentRef(unauthenticated),
        Uint8Array.from([1]),
        validMetadata,
      ),
    );
    await seedOwnerAttachment();
    await assertFails(getBytes(attachmentRef(unauthenticated)));
  });

  test('allow owner create and read', async () => {
    const owner = testEnvironment.authenticatedContext(ownerId);
    const bytes = Uint8Array.from([1, 2, 3]);
    await assertSucceeds(uploadBytes(attachmentRef(owner), bytes, validMetadata));
    const downloaded = await assertSucceeds(getBytes(attachmentRef(owner)));
    assert.deepEqual(new Uint8Array(downloaded), bytes);
  });

  test('deny cross-user create and read', async () => {
    const other = testEnvironment.authenticatedContext(otherUserId);
    await assertFails(
      uploadBytes(attachmentRef(other), Uint8Array.from([1]), validMetadata),
    );
    await seedOwnerAttachment();
    await assertFails(getBytes(attachmentRef(other)));
  });

  test('deny uppercase and noncanonical UUID paths', async () => {
    const owner = testEnvironment.authenticatedContext(ownerId);
    const invalidPaths = [
      `attachments/${ownerId}/${attachmentId.toUpperCase()}`,
      `attachments/${ownerId}/123e4567-e89b-12d3-a456`,
    ];
    for (const objectPath of invalidPaths) {
      await assertFails(
        uploadBytes(
          attachmentRef(owner, objectPath),
          Uint8Array.from([1]),
          validMetadata,
        ),
      );
    }
  });

  test('deny zero-byte and oversized uploads', async () => {
    const owner = testEnvironment.authenticatedContext(ownerId);
    await assertFails(
      uploadBytes(attachmentRef(owner), new Uint8Array(0), validMetadata),
    );
    await assertFails(
      uploadBytes(
        attachmentRef(owner),
        new Uint8Array(100 * 1024 * 1024 + 1),
        validMetadata,
      ),
    );
  });

  test('deny invalid MIME and content type or metadata mutation', async () => {
    const owner = testEnvironment.authenticatedContext(ownerId);
    await assertFails(
      uploadBytes(attachmentRef(owner), Uint8Array.from([1]), {
        contentType: 'application/octet-stream',
      }),
    );
    await seedOwnerAttachment();
    await assertFails(
      updateMetadata(attachmentRef(owner), { contentType: 'image/jpeg' }),
    );
    await assertFails(
      updateMetadata(attachmentRef(owner), {
        customMetadata: { attachmentId, schemaVersion: '2' },
      }),
    );
  });

  test('deny delete even for owner', async () => {
    const owner = testEnvironment.authenticatedContext(ownerId);
    await seedOwnerAttachment();
    await assertFails(deleteObject(attachmentRef(owner)));
  });

  test('deny unrelated paths', async () => {
    const owner = testEnvironment.authenticatedContext(ownerId);
    await assertFails(
      uploadBytes(
        attachmentRef(owner, `public/${attachmentId}`),
        Uint8Array.from([1]),
        validMetadata,
      ),
    );
  });
});
