'use strict';

const {onRequest} = require('firebase-functions/v2/https');
const {defineSecret, defineString} = require('firebase-functions/params');
const {initializeApp, getApps} = require('firebase-admin/app');
const {getAppCheck} = require('firebase-admin/app-check');
const {getAuth} = require('firebase-admin/auth');
const {
  SlidingWindowRateLimiter,
  DailyQuota,
  createAssistantHandler,
  positiveInt,
} = require('./core');
const {createAppCheckVerifier} = require('./app_check');

const geminiKey = defineSecret('GEMINI_API_KEY');

/**
 * Firebase Android app id for SpendSense. This is a public identifier, not a
 * credential: it is already committed in `firebase_options.dart` and
 * `android/app/google-services.json`. Defaulting it keeps a deploy from
 * silently rejecting every request (`app_check_app_id_not_configured`) if the
 * non-secret `.env.<project>` file is absent, while an explicit parameter still
 * wins for a different project or app.
 */
const SPENDSENSE_ANDROID_APP_ID =
  '1:35486869641:android:62072850e90abafabc7e58';
const androidAppId = defineString('SPENDSENSE_ANDROID_APP_ID', {
  default: SPENDSENSE_ANDROID_APP_ID,
});

/**
 * Dedicated least-privilege runtime identity for the deployed function.
 *
 * Cloud Functions v2 runs as the App Engine default service account, which
 * carries `roles/editor`, when `serviceAccount` is omitted. That default is
 * intentionally not used: the identity is stated explicitly so a deploy runs as
 * `assistant-proxy-runtime` (logs + Firebase Auth user lookup only) and never
 * silently inherits editor permissions. There is no fallback to a default
 * identity; if this value is wrong the function fails to serve rather than
 * serving with elevated access.
 */
const RUNTIME_SERVICE_ACCOUNT =
  'assistant-proxy-runtime@spendsense-ota-2026.iam.gserviceaccount.com';

const rateLimiter = new SlidingWindowRateLimiter({
  perMinute: positiveInt(process.env.RATE_LIMIT_PER_MINUTE, 12, {max: 600}),
  globalPerMinute: positiveInt(process.env.RATE_LIMIT_GLOBAL_PER_MINUTE, 180, {
    max: 6000,
  }),
});

// A separate window for verified Firebase UIDs. Sharing one limiter would make
// the per-UID and per-IP keys compete for the same per-key budget only by luck
// of string prefix; separate instances keep the two quotas independent and keep
// the global budget counted exactly once per request.
const identityRateLimiter = new SlidingWindowRateLimiter({
  perMinute: positiveInt(process.env.RATE_LIMIT_PER_USER_PER_MINUTE, 12, {
    max: 600,
  }),
  globalPerMinute: Number.MAX_SAFE_INTEGER,
});

// Daily cost circuit breakers. These are per instance, because Cloud Run
// instances do not share memory; use a shared store if a hard cross-instance
// quota is required. They cap the damage a patient account or many accounts can
// do in a day.
const dailyQuota = new DailyQuota({
  limit: positiveInt(process.env.RATE_LIMIT_DAILY_PER_USER, 100, {max: 5000}),
});
const globalDailyQuota = new DailyQuota({
  limit: positiveInt(process.env.RATE_LIMIT_DAILY_GLOBAL, 2000, {max: 100000}),
});

function appCheckService() {
  if (getApps().length === 0) initializeApp();
  return getAppCheck();
}

const verifyAppCheck = createAppCheckVerifier({
  getAppCheck: appCheckService,
  getExpectedAppId: () => androidAppId.value(),
});

async function verifyUserToken(token) {
  if (getApps().length === 0) initializeApp();
  // checkRevoked adds a server lookup. It is intentional: a disabled or
  // signed-out session must not keep access until token expiry.
  const decoded = await getAuth().verifyIdToken(token, true);
  if (!decoded || typeof decoded.uid !== 'string' || decoded.uid.length === 0) {
    throw new Error('missing_uid');
  }
  return decoded;
}

const handler = createAssistantHandler({
  getApiKey: () => geminiKey.value(),
  getModel: () => process.env.GEMINI_MODEL || 'gemini-2.5-flash',
  env: process.env,
  rateLimiter,
  identityRateLimiter,
  dailyQuota,
  globalDailyQuota,
  verifyAppCheck,
  verifyIdToken: verifyUserToken,
  // NaN would make setTimeout fire immediately; clamp to a safe window that
  // stays inside the 30s function timeout.
  timeoutMs: positiveInt(process.env.UPSTREAM_TIMEOUT_MS, 20_000, {max: 25_000}),
});

/**
 * HTTPS endpoint for the SpendSense assistant.
 *
 * The Gemini key is a Google Secret Manager secret injected at runtime. The
 * client sends no keys. App Check is always required: only a registered
 * SpendSense installation with a valid App Check token can invoke this handler.
 */
exports.assistantProxy = onRequest(
  {
    region: process.env.FUNCTION_REGION || 'asia-south1',
    serviceAccount: RUNTIME_SERVICE_ACCOUNT,
    secrets: [geminiKey],
    timeoutSeconds: 30,
    memory: '256MiB',
    maxInstances: 10,
    invoker: 'public',
  },
  async (request, response) => {
    const result = await handler({
      method: request.method,
      headers: request.headers,
      body: request.body,
      ip: request.ip,
      // The deployed wrapper always requires both App Check and a verified
      // Firebase Authentication ID token. There is no environment bypass.
      appCheckRequired: true,
      requireUserAuth: true,
    });
    response.status(result.status);
    for (const [key, value] of Object.entries(result.headers || {})) {
      response.set(key, value);
    }
    if (result.body === null || result.status === 204) {
      response.end();
    } else {
      response.json(result.body);
    }
  },
);
