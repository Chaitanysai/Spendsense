'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {createAppCheckVerifier} = require('../src/app_check');

const expected = '1:1234567890:android:abcdef123456';

test('accepts a token for the exact configured Android app', async () => {
  let initialized = 0;
  const verify = createAppCheckVerifier({
    getAppCheck: () => ({
      verifyToken: async (token) => {
        assert.equal(token, 'valid-token');
        return {appId: expected};
      },
    }),
    expectedAppId: expected,
    initializeApp: () => initialized++,
  });
  const decoded = await verify('valid-token');
  assert.equal(decoded.appId, expected);
  assert.equal(initialized, 1);
});

test('rejects a token belonging to another app in the same project', async () => {
  const verify = createAppCheckVerifier({
    getAppCheck: () => ({
      verifyToken: async () => ({appId: '1:999:android:other'}),
    }),
    expectedAppId: expected,
  });
  await assert.rejects(() => verify('token'), /app_check_wrong_app/);
});

test('fails closed when the expected Android app id is missing', async () => {
  let verifyCalled = false;
  const verify = createAppCheckVerifier({
    getAppCheck: () => ({
      verifyToken: async () => {
        verifyCalled = true;
        return {appId: expected};
      },
    }),
    expectedAppId: '',
  });
  await assert.rejects(() => verify('token'), /app_check_app_id_not_configured/);
  assert.equal(verifyCalled, false);
});

test('propagates verifier failure and does not swallow it', async () => {
  const verify = createAppCheckVerifier({
    getAppCheck: () => ({
      verifyToken: async () => {
        throw new Error('expired');
      },
    }),
    expectedAppId: expected,
  });
  await assert.rejects(() => verify('token'), /expired/);
});
