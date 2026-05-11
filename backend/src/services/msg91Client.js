const env = require('../config/env');
const logger = require('../utils/logger');

/**
 * Server-side MSG91 client for the Flutter widget flow.
 *
 * The app uses MSG91's SDK to send + verify the OTP on-device. After
 * verification the SDK returns a JWT-style access token, and the backend
 * validates that token with MSG91 before issuing a ShareCab session.
 */

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
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
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

module.exports = { verifyAccessToken };
