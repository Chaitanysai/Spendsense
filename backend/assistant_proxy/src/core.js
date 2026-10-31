'use strict';

const crypto = require('node:crypto');
const {
  TOOL_DECLARATIONS,
  ALLOWED_TOOL_NAMES,
  SYSTEM_PROMPT,
} = require('./tools');

const MAX_BODY_BYTES = 64 * 1024;
const MAX_HISTORY_TURNS = 8;
const MAX_TOOL_ROUNDS = 4;
const MAX_CALLS_PER_ROUND = 8;
const MAX_MESSAGE_CHARS = 2000;
const MAX_TOOL_ARGS_BYTES = 8 * 1024;
const MAX_TOOL_RESPONSE_BYTES = 24 * 1024;
const MAX_RESPONSE_CHARS = 8000;

/**
 * Parses a positive integer from an environment string.
 *
 * Config values come from the deployment environment, so a typo must fall back
 * to the safe default instead of disabling a control. `Number('abc')` is NaN,
 * and `count >= NaN` is always false, which would silently remove a rate limit.
 */
function positiveInt(value, fallback, {max = Number.MAX_SAFE_INTEGER} = {}) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 1) return fallback;
  return Math.min(Math.floor(parsed), max);
}

class SlidingWindowRateLimiter {
  constructor({
    perMinute = 12,
    globalPerMinute = 180,
    windowMs = 60_000,
    now = Date.now,
  } = {}) {
    this.perMinute = perMinute;
    this.globalPerMinute = globalPerMinute;
    this.windowMs = windowMs;
    this.now = now;
    this.clients = new Map();
    this.global = [];
  }

  /**
   * Consume one slot for `key`.
   *
   * `global: false` checks only the per-key window. It is used for the
   * per-UID quota, because the same request already consumed the process-wide
   * budget at the pre-authentication (per-IP) stage.
   */
  check(key, {global = true} = {}) {
    const current = this.now();
    const cutoff = current - this.windowMs;

    if (global) this.global = this.global.filter((at) => at > cutoff);
    let timestamps = this.clients.get(key) || [];
    timestamps = timestamps.filter((at) => at > cutoff);

    if (this.clients.size > 5000) {
      for (const [clientKey, values] of this.clients) {
        const fresh = values.filter((at) => at > cutoff);
        if (fresh.length === 0) this.clients.delete(clientKey);
        else this.clients.set(clientKey, fresh);
      }
    }

    if (
      timestamps.length >= this.perMinute ||
      (global && this.global.length >= this.globalPerMinute)
    ) {
      const oldest = Math.min(
        timestamps[0] ?? current,
        global ? (this.global[0] ?? current) : Number.MAX_SAFE_INTEGER,
      );
      const retryAfter = Math.max(
        1,
        Math.ceil((oldest + this.windowMs - current) / 1000),
      );
      this.clients.set(key, timestamps);
      return {allowed: false, retryAfter};
    }

    timestamps.push(current);
    this.clients.set(key, timestamps);
    if (global) this.global.push(current);
    return {allowed: true, retryAfter: 0};
  }
}

/**
 * Coarse daily budget on top of the per-minute windows.
 *
 * The per-minute limiter protects availability. It does not stop a patient
 * caller from spending a large model bill over a day, or many accounts from
 * doing the same. Cloud Run instances do not share memory, so this is a cost
 * circuit breaker per instance, not a precise global quota; a shared store is
 * still required for a hard cross-instance cap.
 */
class DailyQuota {
  constructor({
    limit = Number.MAX_SAFE_INTEGER,
    now = Date.now,
    windowMs = 86_400_000,
  } = {}) {
    this.limit = limit;
    this.now = now;
    this.windowMs = windowMs;
    this.entries = new Map();
  }

  check(key) {
    const current = this.now();
    const day = Math.floor(current / this.windowMs);
    const existing = this.entries.get(key);
    const entry =
      existing && existing.day === day ? existing : {day, count: 0};
    if (entry.count >= this.limit) {
      this.entries.set(key, entry);
      const retryAfter = Math.max(
        1,
        Math.ceil(((day + 1) * this.windowMs - current) / 1000),
      );
      return {allowed: false, retryAfter};
    }
    entry.count += 1;
    this.entries.set(key, entry);
    return {allowed: true, retryAfter: 0};
  }
}

function headerValue(headers, name) {
  if (!headers || typeof headers !== 'object') return undefined;
  const lower = name.toLowerCase();
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() === lower) {
      if (Array.isArray(value)) return value[0];
      return value;
    }
  }
  return undefined;
}

function parseBody(body) {
  if (body && typeof body === 'object' && !Buffer.isBuffer(body)) {
    return body;
  }
  const text = Buffer.isBuffer(body) ? body.toString('utf8') : String(body ?? '');
  if (Buffer.byteLength(text, 'utf8') > MAX_BODY_BYTES) {
    return {error: 'body_too_large'};
  }
  try {
    return JSON.parse(text);
  } catch {
    return {error: 'invalid_json'};
  }
}

function isPlainObject(value) {
  return (
    value !== null &&
    typeof value === 'object' &&
    !Array.isArray(value) &&
    !Buffer.isBuffer(value)
  );
}

function jsonSize(value) {
  try {
    return Buffer.byteLength(JSON.stringify(value), 'utf8');
  } catch {
    return Number.MAX_SAFE_INTEGER;
  }
}

function bearerToken(value) {
  if (typeof value !== 'string') return null;
  const match = /^Bearer\s+([^\s]+)$/i.exec(value.trim());
  if (!match) return null;
  const token = match[1];
  return token.length > 0 && token.length <= 8192 ? token : null;
}

/**
 * True for addresses that are never a real end-user peer: loopback,
 * link-local, RFC1918/ULA/private IPv6 and the unspecified address.
 *
 * Cloud Functions (2nd gen) runs on Cloud Run, where the TCP peer is the
 * platform's local proxy (for example 169.254.8.130). Treating that peer as the
 * client would put every user in one rate-limit bucket, so in that case the
 * last X-Forwarded-For hop — the address the Google front end appended — is used
 * instead.
 */
function isNonPublicAddress(address) {
  const value = String(address || '').trim().toLowerCase();
  if (value.length === 0) return true;
  const v4 = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/.exec(value);
  const plain = v4 ? v4[1] : value;
  const octets = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(plain);
  if (octets) {
    const [a, b] = [Number(octets[1]), Number(octets[2])];
    if (a === 0 || a === 10 || a === 127) return true;
    if (a === 169 && b === 254) return true;
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    if (a === 100 && b >= 64 && b <= 127) return true;
    return false;
  }
  if (plain === '::1' || plain === '::') return true;
  // IPv6 unique-local (fc00::/7) and link-local (fe80::/10).
  if (/^f[cd][0-9a-f]{2}:/.test(plain) || plain.startsWith('fe8') ||
      plain.startsWith('fe9') || plain.startsWith('fea') ||
      plain.startsWith('feb')) {
    return true;
  }
  return false;
}

function clientIp(request) {
  const direct = String(request.ip || '').trim();
  if (direct && !isNonPublicAddress(direct)) return direct.slice(0, 100);

  const forwarded = headerValue(request.headers, 'x-forwarded-for');
  if (typeof forwarded === 'string' && forwarded.length > 0) {
    const hops = forwarded
      .split(',')
      .map((part) => part.trim())
      .filter((part) => part.length > 0);
    // A caller can prepend arbitrary values, but the platform's edge proxy
    // appends the real peer, so the last hop is the best available identity.
    if (hops.length > 0) return hops[hops.length - 1].slice(0, 100);
  }
  return direct.slice(0, 100) || 'unknown';
}

function validateRequest(body) {
  if (!isPlainObject(body)) {
    return {error: 'invalid_request'};
  }
  const allowedTopLevel = new Set(['message', 'history', 'toolExchanges']);
  for (const key of Object.keys(body)) {
    if (!allowedTopLevel.has(key)) return {error: 'invalid_request'};
  }
  if (
    typeof body.message !== 'string' ||
    body.message.trim().length === 0 ||
    body.message.length > MAX_MESSAGE_CHARS
  ) {
    return {error: 'invalid_message'};
  }

  const rawHistory = body.history ?? [];
  if (!Array.isArray(rawHistory) || rawHistory.length > MAX_HISTORY_TURNS) {
    return {error: 'invalid_history'};
  }
  const history = [];
  for (const turn of rawHistory) {
    if (
      !isPlainObject(turn) ||
      (turn.role !== 'user' && turn.role !== 'model') ||
      typeof turn.text !== 'string' ||
      turn.text.length === 0 ||
      turn.text.length > 1000
    ) {
      return {error: 'invalid_history'};
    }
    history.push({role: turn.role, text: turn.text});
  }

  const rawExchanges = body.toolExchanges ?? [];
  if (!Array.isArray(rawExchanges) || rawExchanges.length > MAX_TOOL_ROUNDS) {
    return {error: 'invalid_tool_exchanges'};
  }
  const toolExchanges = [];
  for (const exchange of rawExchanges) {
    if (!isPlainObject(exchange)) return {error: 'invalid_tool_exchanges'};
    if (
      !Array.isArray(exchange.calls) ||
      !Array.isArray(exchange.responses) ||
      exchange.calls.length === 0 ||
      exchange.calls.length > MAX_CALLS_PER_ROUND ||
      exchange.calls.length !== exchange.responses.length
    ) {
      return {error: 'invalid_tool_exchanges'};
    }
    const calls = [];
    const responses = [];
    for (let i = 0; i < exchange.calls.length; i += 1) {
      const call = exchange.calls[i];
      const response = exchange.responses[i];
      if (
        !isPlainObject(call) ||
        typeof call.name !== 'string' ||
        !ALLOWED_TOOL_NAMES.has(call.name) ||
        !isPlainObject(call.args) ||
        jsonSize(call.args) > MAX_TOOL_ARGS_BYTES
      ) {
        return {error: 'invalid_tool_call'};
      }
      if (
        !isPlainObject(response) ||
        response.name !== call.name ||
        !isPlainObject(response.response) ||
        jsonSize(response.response) > MAX_TOOL_RESPONSE_BYTES
      ) {
        return {error: 'invalid_tool_response'};
      }
      calls.push({name: call.name, args: call.args});
      responses.push({name: response.name, response: response.response});
    }
    toolExchanges.push({calls, responses});
  }

  if (jsonSize(body) > MAX_BODY_BYTES) {
    return {error: 'body_too_large'};
  }

  return {
    value: {
      message: body.message.trim(),
      history,
      toolExchanges,
    },
  };
}

function buildContents({message, history, toolExchanges}) {
  const contents = [];
  for (const turn of history) {
    contents.push({role: turn.role, parts: [{text: turn.text}]});
  }
  contents.push({role: 'user', parts: [{text: message}]});
  for (const exchange of toolExchanges) {
    contents.push({
      role: 'model',
      parts: exchange.calls.map((call) => ({
        functionCall: {name: call.name, args: call.args},
      })),
    });
    contents.push({
      role: 'user',
      parts: exchange.responses.map((response) => ({
        functionResponse: {
          name: response.name,
          response: response.response,
        },
      })),
    });
  }
  return contents;
}

function corsHeaders(origin, env) {
  const configured = (env.ALLOWED_ORIGIN || '').trim();
  if (!configured) return {};
  if (origin !== configured) return {};
  return {
    'Access-Control-Allow-Origin': configured,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers':
      'Content-Type, X-Firebase-AppCheck, X-SpendSense-Client',
    'Access-Control-Max-Age': '600',
    Vary: 'Origin',
  };
}

function baseHeaders(origin, env) {
  return {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    ...corsHeaders(origin, env),
  };
}

function createAssistantHandler({
  fetchImpl = globalThis.fetch,
  getApiKey,
  getModel = () => process.env.GEMINI_MODEL || 'gemini-2.5-flash',
  env = process.env,
  now = Date.now,
  logger = console,
  rateLimiter = new SlidingWindowRateLimiter({now}),
  identityRateLimiter = rateLimiter,
  dailyQuota = new DailyQuota({now}),
  globalDailyQuota = new DailyQuota({now}),
  verifyAppCheck,
  verifyIdToken,
  timeoutMs = 20_000,
} = {}) {
  if (typeof fetchImpl !== 'function') {
    throw new Error('fetch implementation is required');
  }

  async function handle(request) {
    const started = now();
    const requestId = crypto.randomUUID();
    const origin = headerValue(request.headers, 'origin');
    const headers = baseHeaders(origin, env);

    const finish = (status, body, extraHeaders = {}) => {
      try {
        logger.info?.(
          JSON.stringify({
            event: 'assistant_proxy',
            requestId,
            status,
            latencyMs: now() - started,
          }),
        );
      } catch {
        // Logging must never break the request path.
      }
      return {
        status,
        headers: {...headers, ...extraHeaders},
        body,
      };
    };

    if (request.method === 'OPTIONS') {
      return {status: 204, headers, body: null};
    }
    if (request.method !== 'POST') {
      return finish(405, {error: 'method_not_allowed'}, {Allow: 'POST, OPTIONS'});
    }

    const configuredOrigin = (env.ALLOWED_ORIGIN || '').trim();
    if (configuredOrigin && origin && origin !== configuredOrigin) {
      return finish(403, {error: 'origin_not_allowed'});
    }

    // Rate-limit before App Check verification so unauthenticated floods cannot
    // cause unlimited Firebase Admin verification work.
    const rate = rateLimiter.check(clientIp(request));
    if (!rate.allowed) {
      return finish(
        429,
        {error: 'rate_limited', message: 'Too many requests. Try again shortly.'},
        {'Retry-After': String(rate.retryAfter)},
      );
    }

    // Fail closed: App Check is required unless the caller is an isolated test
    // harness that explicitly opts out. The deployed wrapper always passes true.
    const requireAppCheck = request.appCheckRequired ?? true;
    if (requireAppCheck) {
      const token = headerValue(request.headers, 'x-firebase-appcheck');
      if (!verifyAppCheck || typeof token !== 'string' || token.length === 0) {
        return finish(401, {error: 'app_check_required'});
      }
      try {
        await verifyAppCheck(token);
      } catch {
        return finish(401, {error: 'app_check_invalid'});
      }
    }

    // User authentication is additive to App Check. It is never a substitute
    // for app attestation, and no client-supplied uid is trusted.
    const requireUserAuth = request.requireUserAuth ?? true;
    let verifiedUid = null;
    if (requireUserAuth) {
      const token = bearerToken(headerValue(request.headers, 'authorization'));
      if (!token) return finish(401, {error: 'auth_required'});
      if (typeof verifyIdToken !== 'function') {
        return finish(401, {error: 'auth_unavailable'});
      }
      let decoded;
      try {
        decoded = await verifyIdToken(token);
      } catch {
        return finish(401, {error: 'auth_invalid'});
      }
      if (!decoded || typeof decoded.uid !== 'string' || decoded.uid.length === 0) {
        return finish(401, {error: 'auth_invalid'});
      }
      verifiedUid = decoded.uid;
    }

    // Per-identity quota on top of the per-IP one. Mobile carriers put many
    // users behind one NAT address and a caller can rotate addresses, so the
    // IP window alone is not a safe per-user budget. The key is derived from
    // the verified token only; the process-wide budget was already consumed by
    // the pre-authentication check above, so it is not counted twice.
    if (verifiedUid !== null) {
      const userRate = identityRateLimiter.check(`uid:${verifiedUid}`, {
        global: false,
      });
      if (!userRate.allowed) {
        return finish(
          429,
          {
            error: 'rate_limited',
            message: 'Too many requests. Try again shortly.',
          },
          {'Retry-After': String(userRate.retryAfter)},
        );
      }

      // Cost circuit breaker. The per-minute windows stop bursts; this stops
      // one account (or many accounts) from quietly spending all day.
      const userDay = dailyQuota.check(`uid:${verifiedUid}`);
      if (!userDay.allowed) {
        return finish(
          429,
          {
            error: 'daily_quota_reached',
            message: 'The daily assistant limit was reached. Try again tomorrow.',
          },
          {'Retry-After': String(userDay.retryAfter)},
        );
      }
      const globalDay = globalDailyQuota.check('global');
      if (!globalDay.allowed) {
        return finish(
          429,
          {
            error: 'daily_quota_reached',
            message: 'The assistant is at capacity for today. Try again tomorrow.',
          },
          {'Retry-After': String(globalDay.retryAfter)},
        );
      }
    }

    const parsedBody = parseBody(request.body);
    if (parsedBody && parsedBody.error === 'body_too_large') {
      return finish(413, {error: 'request_too_large'});
    }
    if (parsedBody && parsedBody.error === 'invalid_json') {
      return finish(400, {error: 'invalid_json'});
    }
    const validated = validateRequest(parsedBody);
    if (validated.error) {
      return finish(400, {error: validated.error});
    }

    const apiKey = typeof getApiKey === 'function' ? getApiKey() : '';
    if (!apiKey) {
      return finish(503, {
        error: 'assistant_unavailable',
        message: 'Cloud assistance is not configured.',
      });
    }

    const model = getModel();
    const upstreamBody = {
      systemInstruction: {parts: [{text: SYSTEM_PROMPT}]},
      contents: buildContents(validated.value),
      tools: [{functionDeclarations: TOOL_DECLARATIONS}],
      toolConfig: {functionCallingConfig: {mode: 'AUTO'}},
      generationConfig: {
        temperature: 0.1,
        topP: 0.8,
        maxOutputTokens: 1024,
      },
    };

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    let upstream;
    try {
      upstream = await fetchImpl(
        `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(
          model,
        )}:generateContent`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: JSON.stringify(upstreamBody),
          signal: controller.signal,
        },
      );
    } catch (error) {
      clearTimeout(timer);
      if (error && error.name === 'AbortError') {
        return finish(504, {error: 'gemini_timeout'});
      }
      return finish(502, {error: 'gemini_unreachable'});
    }
    clearTimeout(timer);

    if (!upstream || typeof upstream.status !== 'number') {
      return finish(502, {error: 'gemini_unreachable'});
    }
    if (upstream.status === 429) {
      return finish(429, {
        error: 'rate_limited',
        message: 'The assistant is busy. Try again shortly.',
      });
    }
    if (!upstream.ok) {
      return finish(502, {error: 'gemini_error'});
    }

    let payload;
    try {
      payload = await upstream.json();
    } catch {
      return finish(502, {error: 'gemini_invalid_response'});
    }

    const candidate =
      payload &&
      Array.isArray(payload.candidates) &&
      payload.candidates.length > 0
        ? payload.candidates[0]
        : null;
    if (!candidate || !candidate.content) {
      return finish(502, {error: 'gemini_empty_response'});
    }
    const parts = Array.isArray(candidate.content.parts)
      ? candidate.content.parts
      : [];
    let text = '';
    const functionCalls = [];
    for (const part of parts) {
      if (!isPlainObject(part)) continue;
      if (typeof part.text === 'string') {
        text += part.text;
      }
      if (isPlainObject(part.functionCall)) {
        const name = part.functionCall.name;
        if (typeof name !== 'string' || !ALLOWED_TOOL_NAMES.has(name)) {
          return finish(502, {error: 'gemini_unknown_tool'});
        }
        const args = isPlainObject(part.functionCall.args)
          ? part.functionCall.args
          : {};
        if (jsonSize(args) > MAX_TOOL_ARGS_BYTES) {
          return finish(502, {error: 'gemini_invalid_arguments'});
        }
        functionCalls.push({name, args});
        if (functionCalls.length > MAX_CALLS_PER_ROUND) {
          return finish(502, {error: 'gemini_too_many_calls'});
        }
      }
    }

    text = text.trim();
    if (text.length > MAX_RESPONSE_CHARS) {
      text = text.slice(0, MAX_RESPONSE_CHARS);
    }
    if (text.length === 0 && functionCalls.length === 0) {
      return finish(502, {error: 'gemini_empty_response'});
    }

    const usage = payload.usageMetadata || {};
    return finish(200, {
      text,
      functionCalls,
      usage: {
        promptTokens:
          typeof usage.promptTokenCount === 'number'
            ? usage.promptTokenCount
            : null,
        candidateTokens:
          typeof usage.candidatesTokenCount === 'number'
            ? usage.candidatesTokenCount
            : null,
        totalTokens:
          typeof usage.totalTokenCount === 'number'
            ? usage.totalTokenCount
            : null,
      },
    });
  }

  return handle;
}

module.exports = {
  SlidingWindowRateLimiter,
  DailyQuota,
  createAssistantHandler,
  validateRequest,
  buildContents,
  clientIp,
  positiveInt,
  MAX_BODY_BYTES,
  MAX_TOOL_ROUNDS,
  MAX_CALLS_PER_ROUND,
};
