/**
 * MSG91 OTP exchange. The endpoint receives a phone + access token from
 * the client (the SDK already verified the OTP and minted the token),
 * re-validates it via MSG91's verifyAccessToken, and issues our session.
 *
 * We mock `global.fetch` per test to control MSG91's response without
 * needing the real authkey / network. The controller is invoked via
 * the same req/res harness used by other tests.
 */

// Set the MSG91 authkey BEFORE requiring any project module so env.js
// captures it on first load. The network call itself is mocked, so the
// fake value is never transmitted.
process.env.MSG91_AUTH_KEY = process.env.MSG91_AUTH_KEY || 'test-key';

const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

const User = require('../src/models/User');
const authCtrl = require('../src/controllers/authController');
// Direct handle on the cached env so individual tests can flip the
// template id without re-requiring the module tree.
const env = require('../src/config/env');

function makeRes() {
  return {
    statusCode: 200,
    body: undefined,
    status(c) { this.statusCode = c; return this; },
    json(p) { this.body = p; return this; },
  };
}

async function call(handler, { body }) {
  const req = { body };
  const res = makeRes();
  let nextErr;
  await handler(req, res, (err) => { nextErr = err; });
  return { res, err: nextErr };
}

let mongo;
let originalFetch;

beforeAll(async () => {
  mongo = await MongoMemoryServer.create();
  await mongoose.connect(mongo.getUri());
});

afterAll(async () => {
  await mongoose.disconnect();
  await mongo.stop();
});

beforeEach(async () => {
  await User.deleteMany({});
  originalFetch = global.fetch;
});

afterEach(() => {
  global.fetch = originalFetch;
});

function mockMsg91({ ok, type }) {
  global.fetch = async () => ({
    ok,
    status: ok ? 200 : 401,
    text: async () => JSON.stringify({ type, message: ok ? 'verified' : 'invalid' }),
  });
}

describe('verifyMsg91Otp', () => {
  test('valid token + new phone auto-creates user and issues session', async () => {
    mockMsg91({ ok: true, type: 'success' });
    const r = await call(authCtrl.verifyMsg91Otp, {
      body: { phone: '+919999111111', accessToken: 'msg91.jwt.token' },
    });
    expect(r.err).toBeUndefined();
    expect(r.res.body).toEqual(expect.objectContaining({
      accessToken: expect.any(String),
      refreshToken: expect.any(String),
      user: expect.objectContaining({ phone: '+919999111111' }),
    }));
    const user = await User.findOne({ phone: '+919999111111' });
    expect(user).not.toBeNull();
    expect(user.role).toBe('rider');
  });

  test('valid token + existing phone reuses the account', async () => {
    await User.create({
      name: 'Existing',
      phone: '+919999222222',
      role: 'rider',
      passwordHash: 'unused',
    });
    mockMsg91({ ok: true, type: 'success' });
    const r = await call(authCtrl.verifyMsg91Otp, {
      body: { phone: '+919999222222', accessToken: 'msg91.jwt.token' },
    });
    expect(r.err).toBeUndefined();
    expect(r.res.body.user.name).toBe('Existing');
    // Sanity: still only one user document for this phone.
    expect(await User.countDocuments({ phone: '+919999222222' })).toBe(1);
  });

  test('rejected token returns 401 and does NOT create a user', async () => {
    mockMsg91({ ok: false, type: 'error' });
    const r = await call(authCtrl.verifyMsg91Otp, {
      body: { phone: '+919999333333', accessToken: 'tampered.token' },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(401);
    expect(await User.countDocuments({ phone: '+919999333333' })).toBe(0);
  });

  test('missing access token rejected by schema', async () => {
    const r = await call(authCtrl.verifyMsg91Otp, {
      body: { phone: '+919999444444' },
    });
    expect(r.err).toBeDefined();
  });
});

describe('Server-side MSG91 OTP flow (the path /auth/otp/request takes)', () => {
  // /auth/otp/request used to return the dev OTP unconditionally and we
  // patched it to forbid that when MSG91 was configured. Now it goes one
  // step further: it actually SENDS an OTP via MSG91. These tests pin
  // the new behaviour with a mocked MSG91 endpoint so we don't hit the
  // real API in CI.

  test('requestOtp dispatches MSG91 sendOtp when configured', async () => {
    env.msg91.templateId = 'TEMPLATE_TEST';
    const calls = [];
    global.fetch = async (url, opts) => {
      calls.push({ url, opts });
      return {
        ok: true,
        status: 200,
        text: async () =>
          JSON.stringify({ type: 'success', request_id: 'req_42' }),
      };
    };

    const r = await call(authCtrl.requestOtp, {
      body: { phone: '+919999666666' },
    });
    expect(r.err).toBeUndefined();
    expect(r.res.body).toEqual({ requestId: 'req_42' });
    // Must NOT leak the dev OTP back to the client when MSG91 is on.
    expect(r.res.body.debugOtp).toBeUndefined();
    // Sanity: we hit MSG91's send endpoint with template+mobile.
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toContain('/api/v5/otp');
    expect(calls[0].url).toContain('template_id=TEMPLATE_TEST');
    expect(calls[0].url).toContain('mobile=919999666666');
    env.msg91.templateId = '';
  });

  test('requestOtp surfaces MSG91 errors as 502', async () => {
    env.msg91.templateId = 'TEMPLATE_TEST';
    global.fetch = async () => ({
      ok: false,
      status: 400,
      text: async () =>
        JSON.stringify({ type: 'error', message: 'Invalid template id' }),
    });
    const r = await call(authCtrl.requestOtp, {
      body: { phone: '+919999777777' },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(502);
    expect(r.err.message).toContain('Invalid template id');
    env.msg91.templateId = '';
  });

  test('requestOtp returns 503 when MSG91_TEMPLATE_ID is missing', async () => {
    env.msg91.templateId = '';
    const r = await call(authCtrl.requestOtp, {
      body: { phone: '+919999888888' },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(503);
  });

  test('verifyOtp delegates to MSG91 (not the dev OTP) when configured', async () => {
    // Hardcoded dev OTP must NOT pass — only what MSG91 says is valid.
    global.fetch = async () => ({
      ok: false,
      status: 401,
      text: async () => JSON.stringify({ type: 'error', message: 'OTP not match' }),
    });
    const r = await call(authCtrl.verifyOtp, {
      body: { phone: '+919999999999', otp: '123456' },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(401);
    expect(await User.countDocuments({ phone: '+919999999999' })).toBe(0);
  });

  test('verifyOtp issues session when MSG91 confirms the OTP', async () => {
    global.fetch = async () => ({
      ok: true,
      status: 200,
      text: async () => JSON.stringify({ type: 'success', message: 'OTP verified' }),
    });
    const r = await call(authCtrl.verifyOtp, {
      body: { phone: '+919998888888', otp: '424242' },
    });
    expect(r.err).toBeUndefined();
    expect(r.res.body).toEqual(expect.objectContaining({
      accessToken: expect.any(String),
      user: expect.objectContaining({ phone: '+919998888888' }),
    }));
  });
});

describe('Dev OTP fallback (MSG91_DEV_FALLBACK=true)', () => {
  // Opt-in path used while DLT registration is pending. Activated by
  // env.msg91.devFallback — both endpoints skip MSG91 entirely.

  let originalDevFallback;
  let fetchCalls;

  beforeEach(() => {
    originalDevFallback = env.msg91.devFallback;
    env.msg91.devFallback = true;
    // Track whether MSG91 is incorrectly hit in dev mode (it shouldn't be).
    fetchCalls = [];
    global.fetch = async (...args) => {
      fetchCalls.push(args);
      return {
        ok: true,
        status: 200,
        text: async () => JSON.stringify({ type: 'success' }),
      };
    };
  });

  afterEach(() => {
    env.msg91.devFallback = originalDevFallback;
  });

  test('requestOtp returns the dev OTP without calling MSG91', async () => {
    const r = await call(authCtrl.requestOtp, {
      body: { phone: '+919997777777' },
    });
    expect(r.err).toBeUndefined();
    expect(r.res.body).toEqual({ debugOtp: '123456' });
    expect(fetchCalls).toHaveLength(0);
  });

  test('verifyOtp with the dev OTP issues a session, no MSG91 call', async () => {
    const r = await call(authCtrl.verifyOtp, {
      body: { phone: '+919997777777', otp: '123456' },
    });
    expect(r.err).toBeUndefined();
    expect(r.res.body.user.phone).toBe('+919997777777');
    expect(fetchCalls).toHaveLength(0);
  });

  test('verifyOtp with a wrong OTP is rejected even in dev mode', async () => {
    const r = await call(authCtrl.verifyOtp, {
      body: { phone: '+919997777777', otp: '999999' },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(401);
  });
});

