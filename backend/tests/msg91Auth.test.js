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
// Direct handle on the cached env so individual tests can flip dev mode
// without re-requiring the module tree.
const env = require('../src/config/env');

function makeRes() {
  return {
    statusCode: 200,
    headers: {},
    body: undefined,
    status(c) { this.statusCode = c; return this; },
    set(k, v) { this.headers[k] = v; return this; },
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
  env.msg91.devFallback = false;
  env.msg91.widgetId = '';
  env.msg91.widgetAuthToken = '';
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
  test('returns public widget config when backend env provides it', async () => {
    env.msg91.widgetId = 'widget_123';
    env.msg91.widgetAuthToken = 'public_widget_token';

    const r = await call(authCtrl.getMsg91WidgetConfig, { body: {} });

    expect(r.err).toBeUndefined();
    expect(r.res.headers['Cache-Control']).toBe('no-store');
    expect(r.res.body).toEqual({
      enabled: true,
      widgetId: 'widget_123',
      authToken: 'public_widget_token',
    });
  });

  test('returns disabled widget config when public widget env is missing', async () => {
    const r = await call(authCtrl.getMsg91WidgetConfig, { body: {} });

    expect(r.err).toBeUndefined();
    expect(r.res.body).toEqual({ enabled: false });
  });

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

  test('posts authkey + access-token to MSG91 verifyAccessToken', async () => {
    let msg91Request;
    global.fetch = async (url, opts) => {
      msg91Request = { url, opts, body: JSON.parse(opts.body) };
      return {
        ok: true,
        status: 200,
        text: async () => JSON.stringify({ type: 'success', message: 'verified' }),
      };
    };

    const r = await call(authCtrl.verifyMsg91Otp, {
      body: { phone: '+919999555555', accessToken: 'msg91.jwt.token' },
    });
    expect(r.err).toBeUndefined();
    expect(msg91Request.url).toBe(env.msg91.verifyUrl);
    expect(msg91Request.opts.method).toBe('POST');
    expect(msg91Request.opts.headers).toEqual({
      'Content-Type': 'application/json',
      Accept: 'application/json',
    });
    expect(msg91Request.body).toEqual({
      authkey: env.msg91.authKey,
      'access-token': 'msg91.jwt.token',
    });
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

describe('Legacy server OTP endpoints with MSG91 widget flow', () => {
  test('requestOtp is dev-only and does not call MSG91', async () => {
    const calls = [];
    global.fetch = async (...args) => {
      calls.push(args);
      return {
        ok: true,
        status: 200,
        text: async () => JSON.stringify({ type: 'success' }),
      };
    };

    const r = await call(authCtrl.requestOtp, {
      body: { phone: '+919999888888' },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(503);
    expect(r.err.message).toContain('MSG91 Flutter widget SDK');
    expect(calls).toHaveLength(0);
  });

  test('verifyOtp is dev-only and does not accept the hardcoded OTP', async () => {
    const calls = [];
    global.fetch = async (...args) => {
      calls.push(args);
      return {
        ok: true,
        status: 200,
        text: async () => JSON.stringify({ type: 'success' }),
      };
    };

    const r = await call(authCtrl.verifyOtp, {
      body: { phone: '+919999999999', otp: '123456' },
    });
    expect(r.err).toBeDefined();
    expect(r.err.status).toBe(503);
    expect(r.err.message).toContain('/auth/otp/msg91/verify');
    expect(calls).toHaveLength(0);
    expect(await User.countDocuments({ phone: '+919999999999' })).toBe(0);
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
