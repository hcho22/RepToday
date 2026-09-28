// Installed-workerd regression for cross-isolate clock skew on the assertion challenge.
// The gateway and its Durable Object run as two workerd services, so each has its own isolate
// and clock; only the Durable Object's clock is shifted. Real gateway, real SQLite state and real
// P-256 assertions; Premium is the same trusted local double as workerd-auth.mjs. Zero external requests.
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { Miniflare } from 'miniflare';
import { fixtureKey, signedAssertion, APP_PREFIX, TEST_GATE, TEST_BODY_HASH, TEST_TRANSACTION_HASH } from './auth-fixtures.js';
import { VERSION, ORIGIN, CHALLENGE_CLOCK_SKEW_MS, hash, assertionPayload, challengeToken } from '../src/coach-auth-crypto.js';

export async function validateClockSkew({ root, gatewayScript, stateScript }) {
  const key = fixtureKey();
  const rows = [];
  let externalCalls = 0;
  const collect = stream => {
    let pending = '';
    stream.on('data', chunk => {
      pending += chunk.toString(); assert.ok(pending.length <= 262144);
      let boundary;
      while ((boundary = pending.indexOf('\n')) !== -1) {
        const line = pending.slice(0, boundary); pending = pending.slice(boundary + 1);
        try { const row = JSON.parse(line); if (row.event === 'coach_auth_guard') rows.push(row); } catch {}
      }
    });
  };
  const bindings = { COACH_AUTH_GUARD_DIAGNOSTICS: '1', COACH_AUTH_MODE: 'app-attest-storekit-v1',
    CLIENT_SHARED_SECRET: TEST_GATE, APP_ATTEST_APP_PREFIX: APP_PREFIX, APP_STORE_APP_ID: '1', APP_STORE_KEY_ID: APP_PREFIX,
    APP_STORE_ISSUER_ID: '00000000-0000-4000-8000-000000000000', APP_STORE_PRIVATE_KEY: 'TEST-ONLY-INVALID-KEY-NO-APPLE-AUTHORITY' };
  const m = new Miniflare({
    handleRuntimeStdio: (stdout, stderr) => { collect(stdout); collect(stderr); },
    outboundService: () => { externalCalls++; return new Response('local-fixture-rejected', { status: 500 }); },
    workers: [
      { name: 'gateway', modulesRoot: root, scriptPath: gatewayScript, modules: true,
        compatibilityDate: '2025-07-18', compatibilityFlags: ['nodejs_compat'], bindings,
        durableObjects: { COACH_AUTH_STATE: { className: 'SkewedAuthenticationState', scriptName: 'skewed-state', useSQLite: true } } },
      { name: 'skewed-state', modulesRoot: root, scriptPath: stateScript, modules: true,
        compatibilityDate: '2025-07-18', compatibilityFlags: ['nodejs_compat'], bindings },
    ],
  });
  const settle = async (predicate, ms = 3000) => {
    for (const end = Date.now() + ms; !predicate() && Date.now() < end;) await new Promise(r => setTimeout(r, 20));
  };
  try {
    const call = (url, input, headers = {}) => m.dispatchFetch(url, { method: 'POST', headers, body: JSON.stringify(input) });
    const ns = await m.getDurableObjectNamespace('COACH_AUTH_STATE', 'gateway');
    const stub = ns.get(ns.idFromName(VERSION + ':' + hash(key.keyId)));
    const setLag = async lagMs => assert.equal((await stub.fetch('https://fixture-clock.invalid/', {
      method: 'POST', body: JSON.stringify({ lagMs }) })).status, 200);
    const record = async () => (await stub.fetch('https://fixture-record.invalid/')).json();
    const assertChallenge = () => call(ORIGIN, { operation: 'challenge', kind: 'assert', keyId: key.keyId });
    await stub.fetch('https://fixture-seed.invalid/', { method: 'POST', body: JSON.stringify({
      v: VERSION, publicKey: key.publicKey, counter: 0, expiresAt: Date.now() + 600_000 }) });

    // Small realistic lag: the Durable Object's clock trails the Worker that minted the token.
    rows.length = 0;
    for (const lagMs of [0, 1, 25, 250, CHALLENGE_CLOCK_SKEW_MS, -10_000]) {
      await setLag(lagMs);
      const result = await assertChallenge();
      const body = await result.json();
      if (result.status !== 200) await settle(() => rows.length >= 2);
      assert.equal(result.status, 200, `DO clock ${lagMs}ms behind: ${JSON.stringify(body)} ${JSON.stringify(rows)}`);
      assert.equal(typeof body.challenge, 'string');
    }
    await settle(() => rows.length > 0, 300);
    assert.deepEqual(rows, []);

    // Beyond the bound the issue time is still in the future: the same public denial and guard row.
    const beyond = 2 * CHALLENGE_CLOCK_SKEW_MS;
    await setLag(beyond); rows.length = 0;
    const denied = await assertChallenge();
    assert.equal(denied.status, 401); assert.deepEqual(await denied.json(), { error: 'unauthorized' });
    await settle(() => rows.length >= 2);
    const future = rows.find(row => row.stage === 'do_token_entry');
    assert.equal(future?.reason, 'token_future');
    assert.ok(future.deltaMs > CHALLENGE_CLOCK_SKEW_MS && future.deltaMs <= beyond, JSON.stringify(future));
    assert.ok(rows.some(row => row.stage === 'worker_state' && row.reason === 'denied'));

    // Forged, substituted and expired tokens stay denied inside the lagging Durable Object.
    await setLag(25);
    const direct = challenge => stub.fetch('https://security.invalid/', { method: 'POST',
      body: JSON.stringify({ operation: 'challenge', keyId: key.keyId, challenge }) });
    const other = fixtureKey().keyId;
    for (const [label, challenge] of [
      ['forged MAC', challengeToken(key.keyId, '1'.repeat(64), Date.now())],
      ['other key', challengeToken(other, TEST_GATE, Date.now())],
      ['expired', challengeToken(key.keyId, TEST_GATE, Date.now() - 120_000)],
    ]) {
      const result = await direct(challenge);
      assert.equal(result.status, 401, label); assert.deepEqual(await result.json(), { error: 'unauthorized' }, label);
    }

    // End to end with the lagging Durable Object: the signed send reaches the Coach handler
    // (the no-model {} control answers invalid_context) and its exact replay is refused.
    const before = (await record()).counter;
    const issued = await assertChallenge();
    assert.equal(issued.status, 200);
    const { challenge } = await issued.json();
    const assertion = signedAssertion(key, assertionPayload('reply', key.keyId, challenge, TEST_BODY_HASH, TEST_TRANSACTION_HASH), before + 1);
    const headers = { 'X-RepToday-Coach-Auth': JSON.stringify({ operation: 'reply', keyId: key.keyId, challenge,
      assertion: assertion.toString('base64'), transactionJws: 'fixture.purchase.proof' }) };
    const admission = await call('https://runtime-fixture.invalid/admission', {}, headers);
    assert.equal(admission.status, 400); assert.deepEqual(await admission.json(), { error: 'invalid_context' });
    const replay = await call('https://runtime-fixture.invalid/admission', {}, headers);
    assert.equal(replay.status, 401); assert.deepEqual(await replay.json(), { error: 'unauthorized' });
    assert.equal((await record()).counter, before + 1);
    assert.equal(externalCalls, 0);
  } finally { await m.dispose(); }
}
