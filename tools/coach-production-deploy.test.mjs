import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { Cloudflare, DeploymentFailure, TARGET, deploy, gateProbes,
  credentialsFromPacket, readWranglerOAuth, stagingConfig } from './coach-production-deploy.mjs';

// Deliberately non-secret doubles. This suite cannot contact the network or read Keychain.
const credentials = { openAI: 'sk-NONSECRET_TEST_DOUBLE_1234567890',
  clientGate: '0'.repeat(64), wafToken: 'NONSECRET_WAF_TEST_DOUBLE_1234567890' };
const oauth = 'NONSECRET_OAUTH_TEST_DOUBLE';
const account = 'a'.repeat(32), zone = 'b'.repeat(32);
const customPhase = 'http_request_firewall_custom', ratePhase = 'http_ratelimit';
const workerPath = `/accounts/${account}/workers/scripts/${TARGET.worker}`;

function fixture() {
  const state = {
    accounts: [{ id: account }],
    // Pro is a non-secret capability double, not the actual production zone (which is Free).
    zones: [{ id: zone, name: TARGET.zone, status: 'active', account: { id: account }, plan: { name: 'Pro Website' } }],
    exists: false, domains: [], routes: [], rulesets: new Map(), calls: [], reports: [], stages: 0,
    settings: { bindings: [{ name: 'ANTHROPIC_MODEL', type: 'plain_text', text: 'claude-opus-4-8' }],
      observability: { enabled: false }, logpush: false, tail_consumers: [] },
    subdomain: { enabled: false, previews_enabled: false },
    changeset: { added: [{ hostname: TARGET.hostname }], removed: [], updated: [], conflicting: [] },
    failure: null, nextId: 1, probes: 0,
  };
  const nextId = () => (state.nextId++).toString(16).padStart(32, '0');
  function respond(result, status = 200) {
    return new Response(JSON.stringify(status === 200 ? { success: true, result } :
      { success: false, errors: [{ code: status === 404 ? 10003 : 10000 }] }),
    { status, headers: { 'Content-Type': 'application/json' } });
  }
  const fetchImpl = async (url, options) => {
    assert.equal(url.origin, 'https://api.cloudflare.com');
    assert.equal(options.redirect, 'error'); assert.ok(options.signal);
    const endpoint = url.pathname.replace('/client/v4', '') + url.search;
    const body = options.body === undefined ? undefined : JSON.parse(options.body);
    state.calls.push({ endpoint, method: options.method, authorization: options.headers.Authorization, body });
    if (state.failure?.(endpoint, options, body)) return respond(null, 403);
    if (endpoint.startsWith(`/zones/${zone}/rulesets`)) {
      assert.equal(options.headers.Authorization, `Bearer ${credentials.wafToken}`);
      const suffix = endpoint.slice(`/zones/${zone}`.length);
      if (options.method === 'GET' && suffix.includes('/phases/')) {
        const phase = suffix.split('/')[3];
        return state.rulesets.has(phase) ? respond(state.rulesets.get(phase)) : respond(null, 404);
      }
      if (options.method === 'POST' && suffix === '/rulesets') {
        assert.ok(!state.rulesets.has(body.phase));
        const value = { ...body, id: nextId(), rules: body.rules.map(rule => ({ ...rule, id: nextId() })) };
        state.rulesets.set(body.phase, value); return respond(value);
      }
      const ruleset = [...state.rulesets.values()].find(value => value.id === suffix.split('/')[2]);
      assert.ok(ruleset);
      if (options.method === 'POST' && suffix.endsWith('/rules')) {
        ruleset.rules.push({ ...body, id: nextId() }); return respond(ruleset);
      }
      if (options.method === 'PATCH') {
        const rule = ruleset.rules.find(rule => rule.id === suffix.split('/')[4]);
        assert.ok(rule); Object.assign(rule, body); return respond(ruleset);
      }
      assert.fail('Unexpected zone operation');
    }
    assert.equal(options.headers.Authorization, `Bearer ${oauth}`);
    if (endpoint === '/accounts') return respond(state.accounts);
    if (endpoint.startsWith('/zones?')) return respond(state.zones);
    if (endpoint === `/accounts/${account}/workers/scripts`) return respond(state.exists ? [{ id: TARGET.worker }] : []);
    if (endpoint === `/accounts/${account}/workers/domains`) return respond(state.domains);
    if (endpoint === `/zones/${zone}/workers/routes`) return respond(state.routes);
    if (endpoint === workerPath + '/settings') return respond(state.settings);
    if (endpoint === workerPath + '/subdomain') return respond(state.subdomain);
    if (endpoint === workerPath + '/domains/changeset?replace_state=true') return respond(state.changeset);
    if (endpoint === workerPath + '/domains/records') {
      assert.equal(body.override_scope, false); assert.equal(body.override_existing_origin, false);
      assert.equal(body.override_existing_dns_record, false);
      assert.deepEqual(body.origins, [{ hostname: TARGET.hostname, zone_id: zone }]);
      state.domains = [{ hostname: TARGET.hostname, service: TARGET.worker, zone_id: zone, environment: 'production' }];
      return respond(state.domains);
    }
    if (endpoint === workerPath + '/secrets') {
      if (options.method === 'GET') return respond(state.settings.bindings.filter(binding => binding.type === 'secret_text')
        .map(({ name, type }) => ({ name, type })));
      assert.equal(options.method, 'PUT');
      assert.ok(!state.settings.bindings.some(binding => binding.name === body.name));
      state.settings.bindings.push({ name: body.name, type: body.type });
      return respond({ name: body.name, type: body.type });
    }
    assert.fail('Unexpected account operation');
  };
  const cf = new Cloudflare(oauth, credentials.wafToken, fetchImpl);
  const hold = () => state.rulesets.get(customPhase)?.rules.find(rule => rule.ref === 'reptoday_coach_deployment_hold_v1');
  const run = (overrides = {}) => deploy({ cf, credentials,
    stageWorker: async confirmedAccount => {
      assert.equal(confirmedAccount, account); assert.equal(hold()?.enabled, true);
      state.stages++; state.exists = true;
    }, report: line => state.reports.push(line), probe: async gate => {
      assert.equal(gate, credentials.clientGate); assert.equal(hold()?.enabled, false); state.probes++;
    }, ...overrides });
  return { state, cf, run, hold };
}

const stopped = code => error => error instanceof DeploymentFailure && error.code === code;
const mutations = state => state.calls.filter(call => ['PUT', 'PATCH', 'POST'].includes(call.method) &&
  !call.endpoint.includes('/changeset?'));

test('approved deployment stays closed through staging, installs both safeguards, and uploads only two existing values', async () => {
  const { state, run, hold } = fixture(); await run();
  assert.equal(state.stages, 1); assert.equal(hold().enabled, false); assert.equal(state.probes, 1);
  const uploads = state.calls.filter(call => call.method === 'PUT' && call.endpoint.endsWith('/secrets'));
  assert.deepEqual(uploads.map(call => call.body.name).sort(), ['CLIENT_SHARED_SECRET', 'OPENAI_API_KEY']);
  assert.equal(uploads.find(call => call.body.name === 'OPENAI_API_KEY').body.text, credentials.openAI);
  assert.equal(uploads.find(call => call.body.name === 'CLIENT_SHARED_SECRET').body.text, credentials.clientGate);
  assert.ok(state.calls.every(call => !(JSON.stringify(call.body) ?? '').includes(credentials.wafToken)));
  assert.equal(state.calls.filter(call => call.authorization === `Bearer ${credentials.wafToken}`)
    .every(call => call.endpoint.startsWith(`/zones/${zone}/rulesets`)), true);
  assert.ok(state.reports.every(line => !Object.values(credentials).some(value => line.includes(value)) && !line.includes(account)));
  assert.equal(state.reports.at(-1), `deployed: ${TARGET.worker} ${TARGET.origin}; live model QA pending`);
});

test('rerun preserves server secret bindings and restores the hold during staging', async () => {
  const { state, run, hold } = fixture(); await run(); state.calls = []; await run();
  assert.equal(state.stages, 2); assert.equal(hold().enabled, false);
  assert.equal(state.calls.filter(call => call.method === 'PUT' && call.endpoint.endsWith('/secrets')).length, 0);
});

test('ambiguous account stops before any mutation', async () => {
  const { state, run } = fixture(); state.accounts.push({ id: 'c'.repeat(32) });
  await assert.rejects(run(), stopped('account')); assert.equal(mutations(state).length, 0);
});

test('wrong zone account and inactive zone each stop before mutation', async () => {
  for (const change of [{ account: { id: 'c'.repeat(32) } }, { status: 'pending' }]) {
    const { state, run } = fixture(); Object.assign(state.zones[0], change);
    await assert.rejects(run(), stopped('zone')); assert.equal(mutations(state).length, 0);
  }
});

test('actual Free plan and unknown plans stop before any WAF, Worker, routing or secret mutation', async () => {
  for (const plan of ['Free Website', 'Unknown Subscription']) {
    const { state, run } = fixture(); state.zones[0].plan.name = plan;
    await assert.rejects(run(), stopped('rate-plan'));
    assert.equal(mutations(state).length, 0); assert.equal(state.stages, 0);
    assert.equal(state.calls.some(call => call.authorization === `Bearer ${credentials.wafToken}`), false);
  }
});

test('absent WAF authority cannot stage or expose the Worker', async () => {
  const { state, run } = fixture(); state.failure = endpoint => endpoint.includes('/rulesets');
  await assert.rejects(run(), stopped('scope')); assert.equal(state.stages, 0); assert.equal(mutations(state).length, 0);
});

test('unrelated skip rules and occupied rate capacity stop without changing the zone', async () => {
  for (const phase of [customPhase, ratePhase]) {
    const { state, run } = fixture();
    state.rulesets.set(phase, { id: 'd'.repeat(32), kind: 'zone', phase,
      rules: [{ id: 'e'.repeat(32), ref: 'unrelated', action: phase === customPhase ? 'skip' : 'block', enabled: true }] });
    await assert.rejects(run(), stopped('rules')); assert.equal(mutations(state).length, 0);
  }
});

test('unrelated custom block rules are preserved', async () => {
  const { state, run } = fixture(); const existing = { id: 'e'.repeat(32), ref: 'unrelated',
    action: 'block', enabled: true, expression: '(http.host eq "unrelated.reptoday.app")' };
  state.rulesets.set(customPhase, { id: 'd'.repeat(32), kind: 'zone', phase: customPhase, rules: [existing] });
  await run(); assert.deepEqual(state.rulesets.get(customPhase).rules[0], existing);
});

test('an owned rate rule with weaker parameters stops instead of being silently rewritten', async () => {
  const { state, run } = fixture(); await run(); state.calls = [];
  state.rulesets.get(ratePhase).rules[0].ratelimit.requests_per_period = 100;
  await assert.rejects(run(), stopped('rules')); assert.equal(mutations(state).length, 0);
});

test('persistence, tails, logging, and unexpected secret bindings fail the settings boundary', async () => {
  for (const change of [
    settings => settings.bindings.push({ name: 'DATABASE', type: 'kv_namespace' }),
    settings => settings.bindings.push({ name: 'ANTHROPIC_API_KEY', type: 'secret_text' }),
    settings => { settings.tail_consumers = [{ service: 'other' }]; },
    settings => { settings.observability.enabled = true; },
    settings => { settings.logpush = true; },
  ]) {
    const { state, run } = fixture(); state.exists = true; change(state.settings);
    await assert.rejects(run(), stopped('settings')); assert.equal(mutations(state).length, 0);
  }
});

test('a conflicting custom-domain owner is refused before any mutation', async () => {
  const { state, run } = fixture(); state.domains.push({ hostname: TARGET.hostname,
    service: 'other-worker', zone_id: zone, environment: 'production' });
  await assert.rejects(run(), stopped('route')); assert.equal(mutations(state).length, 0);
});

test('exact and wildcard legacy routes to the approved hostname are refused', async () => {
  for (const pattern of ['coach.reptoday.app/*', '*.reptoday.app/*', 'https://*.reptoday.app/coach', '*/*']) {
    const { state, run } = fixture(); state.routes.push({ pattern, script: 'other-worker' });
    await assert.rejects(run(), stopped('route')); assert.equal(mutations(state).length, 0);
  }
});

test('DNS conflict after staging leaves the hold active and uploads no credentials', async () => {
  const { state, run, hold } = fixture(); state.changeset.conflicting.push({ hostname: TARGET.hostname });
  await assert.rejects(run(), stopped('route')); assert.equal(hold().enabled, true);
  assert.equal(state.calls.some(call => call.method === 'PUT' && call.endpoint.endsWith('/secrets')), false);
});

test('stage failure leaves the hold active and uploads no credentials', async () => {
  const { state, run, hold } = fixture();
  await assert.rejects(run({ stageWorker: async () => { throw new DeploymentFailure('wrangler'); } }), stopped('wrangler'));
  assert.equal(hold().enabled, true); assert.equal(state.calls.some(call => call.method === 'PUT'), false);
});

test('public development and preview URLs must be disabled before secrets are sent', async () => {
  for (const field of ['enabled', 'previews_enabled']) {
    const { state, run, hold } = fixture(); state.subdomain[field] = true;
    await assert.rejects(run(), stopped('settings')); assert.equal(hold().enabled, true);
    assert.equal(state.calls.some(call => call.method === 'PUT'), false);
  }
});

test('credential upload rejection leaves hold active and never attaches the hostname', async () => {
  const { state, run, hold } = fixture(); state.failure = (endpoint, options) => endpoint.endsWith('/secrets') && options.method === 'PUT';
  await assert.rejects(run(), stopped('http')); assert.equal(hold().enabled, true); assert.deepEqual(state.domains, []);
});

test('failed paid-call-free gate probe re-closes the hostname', async () => {
  const { run, hold } = fixture();
  await assert.rejects(run({ probe: async () => { throw new DeploymentFailure('gate'); } }), stopped('gate'));
  assert.equal(hold().enabled, true);
});

test('uncertain hold-release response also re-closes instead of leaving an unverified release', async () => {
  const { state, run, hold } = fixture();
  let failed = false;
  state.failure = (endpoint, options, body) => {
    if (!failed && endpoint.includes('/rulesets/') && options.method === 'PATCH' && body.enabled === false) {
      // Simulate the server applying the release but the client receiving an error response.
      hold().enabled = false; failed = true; return true;
    }
    return false;
  };
  await assert.rejects(run(), stopped('scope')); assert.equal(hold().enabled, true); assert.equal(state.probes, 0);
});

test('transport rejects out-of-zone WAF, foreign Worker and unsafe domain override operations', async () => {
  const { cf, state } = fixture(); cf.setScope(account, zone);
  await assert.rejects(cf.zoneRequest('/workers/scripts/foreign/secrets', 'PUT', {}), stopped('scope'));
  await assert.rejects(cf.accountRequest(`/accounts/${account}/workers/scripts/foreign/secrets`, 'PUT', {}), stopped('scope'));
  await assert.rejects(cf.accountRequest(workerPath + '/domains/records', 'PUT', {
    override_existing_origin: true, override_existing_dns_record: true, origins: [{ hostname: TARGET.hostname, zone_id: zone }],
  }), stopped('route'));
  assert.equal(state.calls.length, 0);
});

test('transport refuses redirects and exposes no raw diagnostic values', async () => {
  const cf = new Cloudflare(oauth, credentials.wafToken, async () => { throw new Error(credentials.openAI); });
  await assert.rejects(cf.accountRequest('/accounts'), error => error.message === 'Deployment stopped' && error.code === 'http');
  const redirected = new Cloudflare(oauth, credentials.wafToken, async () => ({ redirected: true, url: 'https://foreign.invalid' }));
  await assert.rejects(redirected.accountRequest('/accounts'), stopped('http'));
});

test('gate probes use only malformed JSON and check missing, wrong and correct authorization without provider input', async () => {
  const requests = [];
  await gateProbes(credentials.clientGate, async (url, options) => {
    assert.equal(url, TARGET.origin); assert.equal(options.body, '{'); assert.equal(options.redirect, 'error');
    requests.push(options);
    const authorized = options.headers.Authorization === `Bearer ${credentials.clientGate}`;
    return new Response(JSON.stringify({ error: authorized ? 'invalid JSON' : 'unauthorized' }), { status: authorized ? 400 : 401 });
  });
  assert.equal(requests.length, 3); assert.equal(requests[0].headers.Authorization, undefined);
  await assert.rejects(gateProbes(credentials.clientGate, async () => new Response('{}', { status: 200 })), stopped('gate'));
});

test('input protocol accepts only the three known existing credentials', () => {
  assert.equal(credentialsFromPacket(credentials), credentials);
  for (const value of [{ ...credentials, extra: 'unapproved' }, { ...credentials, clientGate: '' },
    { ...credentials, openAI: credentials.wafToken }]) assert.throws(() => credentialsFromPacket(value), stopped('input'));
});

test('staging configuration consumed by Wrangler has no public route, storage, logging, account ID or secrets', () => {
  const config = stagingConfig('/nonsecret-test-repository');
  assert.equal(config.name, TARGET.worker); assert.equal(config.workers_dev, false); assert.equal(config.preview_urls, false);
  assert.deepEqual(config.routes, []); assert.deepEqual(config.observability, { enabled: false }); assert.equal(config.logpush, false);
  assert.deepEqual(Object.keys(config).sort(), ['compatibility_date', 'logpush', 'main', 'name', 'observability',
    'preview_urls', 'routes', 'send_metrics', 'vars', 'workers_dev']);
  assert.deepEqual(config.vars, { ANTHROPIC_MODEL: 'claude-opus-4-8' });
});

test('Wrangler credential reader honors installed macOS path and refuses environment overrides', async () => {
  const home = await fs.mkdtemp(path.join(process.cwd(), 'build/coach-auth-double-'));
  try {
    const directory = path.join(home, 'Library/Preferences/.wrangler/config'); await fs.mkdir(directory, { recursive: true });
    await fs.writeFile(path.join(directory, 'default.toml'), `oauth_token = "${oauth}"\nexpiration_time = "2100-01-01T00:00:00Z"\n`);
    assert.equal(await readWranglerOAuth(home, {}), oauth);
    await assert.rejects(readWranglerOAuth(home, { CLOUDFLARE_API_TOKEN: 'NONSECRET_OVERRIDE' }), stopped('auth'));
    await fs.mkdir(path.join(home, '.wrangler/config'), { recursive: true });
    await fs.writeFile(path.join(home, '.wrangler/config/default.toml'), `oauth_token = "NONSECRET_PREFERRED_DOUBLE"\nexpiration_time = "2100-01-01T00:00:00Z"\n`);
    assert.equal(await readWranglerOAuth(home, {}), 'NONSECRET_PREFERRED_DOUBLE');
    await fs.writeFile(path.join(home, '.wrangler/config/default.toml'), `oauth_token = "NONSECRET_EXPIRED_DOUBLE"\nexpiration_time = "2000-01-01T00:00:00Z"\n`);
    await assert.rejects(readWranglerOAuth(home, {}), stopped('auth'));
  } finally { await fs.rm(home, { recursive: true, force: true }); }
});
