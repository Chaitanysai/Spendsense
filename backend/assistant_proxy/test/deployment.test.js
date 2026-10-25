'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..', '..', '..');
const functionIndex = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'index.js'),
  'utf8',
);
const firebaseJson = JSON.parse(
  fs.readFileSync(path.join(repoRoot, 'firebase.json'), 'utf8'),
);
const firebaseRc = JSON.parse(
  fs.readFileSync(path.join(repoRoot, '.firebaserc'), 'utf8'),
);

test('deployed function declares the Secret Manager key and App Check', () => {
  assert.match(functionIndex, /defineSecret\('GEMINI_API_KEY'\)/);
  assert.match(functionIndex, /secrets:\s*\[geminiKey\]/);
  assert.match(functionIndex, /defineString\('SPENDSENSE_ANDROID_APP_ID'/);
  assert.match(functionIndex, /createAppCheckVerifier/);
  assert.match(functionIndex, /getExpectedAppId/);
  assert.match(functionIndex, /getAuth\(\)\.verifyIdToken\(token,\s*true\)/);
  assert.match(functionIndex, /verifyIdToken:\s*verifyUserToken/);
  assert.match(functionIndex, /appCheckRequired:\s*true/);
  assert.match(functionIndex, /requireUserAuth:\s*true/);
  assert.doesNotMatch(functionIndex, /REQUIRE_APP_CHECK/);
  assert.doesNotMatch(functionIndex, /process\.env\.GEMINI_API_KEY/);
});

test('function resource limits and public transport are explicit', () => {
  assert.match(functionIndex, /invoker:\s*'public'/);
  assert.match(functionIndex, /timeoutSeconds:\s*30/);
  assert.match(functionIndex, /maxInstances:\s*10/);
  assert.match(functionIndex, /memory:\s*'256MiB'/);
});

test('assistantProxy runs as the dedicated runtime identity', () => {
  assert.match(
    functionIndex,
    /RUNTIME_SERVICE_ACCOUNT =\s*\n?\s*'assistant-proxy-runtime@spendsense-ota-2026\.iam\.gserviceaccount\.com'/,
  );
  assert.match(functionIndex, /serviceAccount:\s*RUNTIME_SERVICE_ACCOUNT/);
  assert.match(
    functionIndex,
    /region:\s*process\.env\.FUNCTION_REGION \|\| 'asia-south1'/,
  );
});

test('assistantProxy never selects an editor-bearing default identity', () => {
  assert.doesNotMatch(
    functionIndex,
    /serviceAccount:\s*['"][^'"]*appspot\.gserviceaccount\.com['"]/,
  );
  assert.doesNotMatch(
    functionIndex,
    /serviceAccount:\s*['"][^'"]*-compute@developer\.gserviceaccount\.com['"]/,
  );
  assert.doesNotMatch(functionIndex, /serviceAccount:\s*process\.env\./);
});

test('dedicated runtime identity change leaves secrets and auth untouched', () => {
  assert.match(functionIndex, /defineSecret\('GEMINI_API_KEY'\)/);
  assert.match(functionIndex, /secrets:\s*\[geminiKey\]/);
  assert.match(functionIndex, /getApiKey:\s*\(\)\s*=>\s*geminiKey\.value\(\)/);
  assert.match(functionIndex, /verifyIdToken:\s*verifyUserToken/);
  assert.match(functionIndex, /appCheckRequired:\s*true/);
  assert.match(functionIndex, /requireUserAuth:\s*true/);
});

test('Firebase deployment target is explicit and points at the function', () => {
  assert.equal(firebaseRc.projects.default, 'spendsense-ota-2026');
  assert.equal(firebaseJson.functions.source, 'backend/assistant_proxy');
  assert.equal(firebaseJson.functions.runtime, 'nodejs22');
});

test('proxy function does not contain a hardcoded Gemini key value', () => {
  assert.doesNotMatch(functionIndex, /AIza[0-9A-Za-z_-]{20,}/);
  assert.doesNotMatch(functionIndex, /x-goog-api-key['"]?\s*:\s*['"][^'"]+['"]/);
});
