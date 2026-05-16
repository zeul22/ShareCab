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

  // Truncated token preview for logs — never log the full token (it's
  // a JWT-shaped credential good for ~10 minutes at MSG91).
  const tokenPreview = accessToken.length > 12
    ? `${accessToken.slice(0, 6)}…${accessToken.slice(-4)} (len=${accessToken.length})`
    : `len=${accessToken.length}`;

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
    // Map MSG91's opaque numeric `code` to an actionable hint.
    // Determined empirically by probing the verify endpoint with known
    // bad inputs (see PR notes). MSG91 doesn't document these codes
    // publicly, so the mapping is best-effort and we always include
    // the raw code/message so a future code shift is obvious in logs.
    //
    //   code 201 → auth-key rejected outright (server-side MSG91_AUTH_KEY
    //              is wrong, or the widget tokenAuth was pasted there by
    //              mistake)
    //   code 418 → auth-key OK, but the access-token failed verification.
    //              Causes: token expired, widget mints with a different
    //              account's JWT secret than this auth-key, widget lacks
    //              Mobile Integration / JWT mode, the wrong field was
    //              extracted from the SDK response, or MSG91 API Security
    //              rejected Cloud Run's non-whitelisted outbound IP.
    let hint = '';
    if (body?.code === '201') {
      hint = ' [MSG91_AUTH_KEY appears invalid — re-check the account-level '
        + 'authkey in MSG91 console → Account → API; do NOT use the widget tokenAuth here]';
    } else if (body?.code === '418') {
      hint = ' [auth-key accepted by MSG91, access-token rejected — '
        + 'check widget JWT/Mobile Integration is enabled AND that the '
        + 'configured widget belongs to the same MSG91 account as MSG91_AUTH_KEY. '
        + 'Also check MSG91 API Security/IP whitelist: Cloud Run outbound IPs '
        + 'are not static unless you configure Serverless VPC + Cloud NAT]';
    }
    logger.warn(
      `MSG91 verify rejected: status=${res.status} code=${body?.code || '?'} type=${body?.type || 'unknown'} ` +
        `msg="${body?.message || text || ''}" token=${tokenPreview}${hint}`,
    );
    return {
      ok: false,
      status: res.status,
      code: body?.code,
      type: body?.type,
      message: body?.message || text || null,
      hint: hint.trim(),
      raw: body,
    };
  } catch (err) {
    logger.error(`MSG91 verify HTTP failure: ${err.message} token=${tokenPreview}`);
    return { ok: false, reason: 'network', error: err.message };
  }
}

module.exports = { verifyAccessToken };
