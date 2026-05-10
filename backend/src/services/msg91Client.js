const env = require('../config/env');
const logger = require('../utils/logger');

/**
 * Server-side MSG91 client. Two integration paths are supported:
 *
 *   1. Server-driven OTP (default for the Flutter app today). Backend
 *      calls `sendOtp` to dispatch the SMS, the user types the code,
 *      backend calls `verifyOtp` to confirm. No client SDK required.
 *
 *   2. Widget SDK path. Flutter app uses MSG91's widget SDK to do
 *      send + verify entirely on the device, then hands us a JWT-style
 *      access token which we validate via `verifyAccessToken`. Useful
 *      if you ever want the SDK's built-in retry / multi-channel UI.
 *
 * MSG91 normalises mobile numbers to country-code-prefixed digits with
 * NO leading `+` (e.g. `917352448644`). Helpers below take care of
 * the conversion so callers can pass `+91…` or plain `91…`.
 */

const BASE_URL = 'https://control.msg91.com/api/v5';

function normalizeMobile(raw) {
  let m = String(raw || '').replace(/\D/g, '');
  // India default — if the caller gave a 10-digit mobile, prefix the
  // country code. Anything already prefixed (12+ digits) is left alone.
  if (m.length === 10) m = `91${m}`;
  return m;
}

/**
 * Send an OTP to [mobile] using the configured DLT template. Returns
 * `{ ok, requestId }` on success. Errors carry MSG91's message verbatim
 * so the API surface upstream can pass them through to the user.
 */
async function sendOtp({ mobile }) {
  if (!env.msg91.authKey) {
    return { ok: false, reason: 'MSG91_AUTH_KEY not set' };
  }
  if (!env.msg91.templateId) {
    return { ok: false, reason: 'MSG91_TEMPLATE_ID not set' };
  }
  const m = normalizeMobile(mobile);
  if (!m) return { ok: false, reason: 'Invalid mobile' };

  const url = `${BASE_URL}/otp?template_id=${encodeURIComponent(env.msg91.templateId)}&mobile=${encodeURIComponent(m)}`;
  // Log the normalized mobile + masked template id so we can trace
  // request/verify against the exact same upstream record.
  logger.info(
    `MSG91 sendOtp → mobile=${m} template_id=${maskId(env.msg91.templateId)}`,
  );
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        authkey: env.msg91.authKey,
      },
      // Body is required (even if empty) for the OTP send call.
      body: JSON.stringify({}),
    });
    const text = await res.text();
    let body = {};
    try { body = text ? JSON.parse(text) : {}; } catch (_) { /* keep default */ }
    logger.info(
      `MSG91 sendOtp ← status=${res.status} type=${body.type} message=${body.message || ''}`,
    );
    if (res.ok && body.type === 'success') {
      return { ok: true, requestId: body.request_id };
    }
    logger.warn(
      `MSG91 sendOtp rejected: status=${res.status} type=${body.type} message=${body.message}`,
    );
    return { ok: false, status: res.status, message: body.message, raw: body };
  } catch (err) {
    logger.error(`MSG91 sendOtp HTTP failure: ${err.message}`);
    return { ok: false, reason: 'network', error: err.message };
  }
}

// Masking helper so log output never leaks the full secret.
function maskId(s) {
  if (!s) return '<empty>';
  if (s.length <= 6) return '***';
  return `${s.slice(0, 4)}…${s.slice(-2)}`;
}

/**
 * Verify an OTP that the user typed in. MSG91 keeps the request state
 * server-side, so we only need (mobile, otp). Returns `{ ok }`.
 */
async function verifyOtp({ mobile, otp }) {
  if (!env.msg91.authKey) {
    return { ok: false, reason: 'MSG91_AUTH_KEY not set' };
  }
  const m = normalizeMobile(mobile);
  if (!m) return { ok: false, reason: 'Invalid mobile' };
  if (!otp) return { ok: false, reason: 'Missing OTP' };

  const url = `${BASE_URL}/otp/verify?mobile=${encodeURIComponent(m)}&otp=${encodeURIComponent(otp)}`;
  // Log mobile only; the OTP itself stays out of logs.
  logger.info(`MSG91 verifyOtp → mobile=${m}`);
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        authkey: env.msg91.authKey,
      },
    });
    const text = await res.text();
    let body = {};
    try { body = text ? JSON.parse(text) : {}; } catch (_) { /* keep default */ }
    logger.info(
      `MSG91 verifyOtp ← status=${res.status} type=${body.type} message=${body.message || ''}`,
    );
    if (res.ok && body.type === 'success') {
      return { ok: true, raw: body };
    }
    logger.warn(
      `MSG91 verifyOtp rejected: status=${res.status} type=${body.type} message=${body.message}`,
    );
    return { ok: false, status: res.status, message: body.message, raw: body };
  } catch (err) {
    logger.error(`MSG91 verifyOtp HTTP failure: ${err.message}`);
    return { ok: false, reason: 'network', error: err.message };
  }
}

async function verifyAccessToken({ accessToken }) {
  const authKey = env.msg91.authKey;
  if (!authKey) {
    // Stub mode: caller should treat absence of authkey as "MSG91
    // disabled" and reject the verify endpoint upstream. We return a
    // sentinel so test paths can still run without real credentials.
    return { ok: false, stub: true, reason: 'MSG91_AUTH_KEY not set' };
  }
  if (!accessToken || typeof accessToken !== 'string') {
    return { ok: false, reason: 'Missing access token' };
  }

  try {
    const res = await fetch(env.msg91.verifyUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ authkey: authKey, 'access-token': accessToken }),
    });
    const text = await res.text();
    let body = {};
    try {
      body = text ? JSON.parse(text) : {};
    } catch (_) {
      // MSG91 occasionally returns plain text on auth failure.
    }
    // MSG91's success response uses `type: "success"`. Anything else —
    // expired token, mismatched authkey, signature failure — is a
    // verification failure and we MUST reject.
    if (res.ok && body && body.type === 'success') {
      return { ok: true, raw: body };
    }
    logger.warn(
      `MSG91 verify rejected: status=${res.status} type=${body?.type || 'unknown'}`,
    );
    return { ok: false, status: res.status, raw: body };
  } catch (err) {
    logger.error(`MSG91 verify HTTP failure: ${err.message}`);
    return { ok: false, reason: 'network', error: err.message };
  }
}

module.exports = { sendOtp, verifyOtp, verifyAccessToken, normalizeMobile };
