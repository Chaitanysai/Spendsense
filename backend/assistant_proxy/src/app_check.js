'use strict';

/**
 * Creates the server-side App Check verifier.
 *
 * Firebase Admin verifies the token signature and project. We additionally
 * require the decoded token to belong to the exact Android app registered for
 * SpendSense, so a token from another app in the same Firebase project cannot
 * be reused. If the expected app id is not configured, verification fails
 * closed.
 */
function createAppCheckVerifier({
  getAppCheck,
  expectedAppId,
  getExpectedAppId,
  initializeApp,
} = {}) {
  return async function verifyAppCheck(token) {
    if (typeof getAppCheck !== 'function') {
      throw new Error('app_check_not_configured');
    }
    const expected =
      typeof getExpectedAppId === 'function'
        ? String(getExpectedAppId() || '').trim()
        : String(expectedAppId || '').trim();
    if (!expected) throw new Error('app_check_app_id_not_configured');

    if (typeof initializeApp === 'function') initializeApp();
    const decoded = await getAppCheck().verifyToken(token);
    if (!decoded || decoded.appId !== expected) {
      throw new Error('app_check_wrong_app');
    }
    return decoded;
  };
}

module.exports = {createAppCheckVerifier};
