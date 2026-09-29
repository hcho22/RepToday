import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { STAGING, STAGING_SECRET_NAMES, StagingCloudflare, deployStaging, inspectStaging, teardownStaging, stagingProbes,
  stagingWorkerConfig, stagingOrigin, stagingLines, stagingFailureOutput } from './coach-staging.mjs';
import { DeploymentFailure, TARGET } from './coach-production-deploy.mjs';

// Cloudflare API and Worker doubles only: no auth file, Keychain, network or production resource.
const account = 'a'.repeat(32), stagingNamespace = 'c'.repeat(32), productionNamespace = 'f'.repeat(32);
const revision = 'd'.repeat(40), oauth = 'NONSECRET_OAUTH_TEST_DOUBLE', subdomain = 'fixture-account';
const origin = `https://${STAGING}.${subdomain}.workers.dev/coach`;
const apple = { appPrefix: 'FIXTURE001', appID: '123456', keyID: 'FIXTURE002', issuerID: '00000000-0000-0000-0000-000000000000',
  privateKey: generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).privateKey.export({ type: 'pkcs8', format: 'pem' }) };
const stopped = code => error => error instanceof DeploymentFailure && error.code === code;

function fixture() {
  const state = { accounts: [{ id: account }], subdomain: { subdomain }, scripts: [TARGET.worker], secrets: new Map(), calls: [],
    namespaces: [{ id: productionNamespace, class: 'CoachAuthenticationState', script: TARGET.worker, use_sqlite: true }],
    domains: [{ hostname: TARGET.hostname, service: TARGET.worker }], scriptSubdomain: { enabled: true, previews_enabled: false },
    extraBindings: [], vars: null, deleteRemoves: true, stageWorkerCalls: 0 };
  const settings = () => ({ bindings: [
    ...Object.entries(state.vars ?? {}).map(([name, text]) => ({ name, type: 'plain_text', text })),
    { name: 'COACH_AUTH_STATE', type: 'durable_object_namespace', class_name: 'CoachAuthenticationState', namespace_id: stagingNamespace },
    ...[...state.secrets.keys()].map(name => ({ name, type: 'secret_text' })), ...state.extraBindings],
    observability: { enabled: false }, logpush: false, tail_consumers: [] });
  const ok = result => new Response(JSON.stringify({ success: true, result }), { status: 200 });
  const fetchImpl = async (url, init) => {
    const endpoint = url.pathname.replace('/client/v4', '') + url.search;
    const call = { method: init.method, endpoint, body: init.body ? JSON.parse(init.body) : undefined,
      authorization: init.headers.Authorization };
    state.calls.push(call);
    const script = `/accounts/${account}/workers/scripts/${STAGING}`;
    if (endpoint === '/accounts') return ok(state.accounts);
    if (endpoint === `/accounts/${account}/workers/subdomain`) return ok(state.subdomain);
    if (endpoint === `/accounts/${account}/workers/scripts`) return ok(state.scripts.map(id => ({ id })));
    if (endpoint === `/accounts/${account}/workers/durable_objects/namespaces`) return ok(state.namespaces);
    if (endpoint === `/accounts/${account}/workers/domains`) return ok(state.domains);
    if (endpoint === `${script}/settings`) return ok(settings());
    if (endpoint === `${script}/subdomain`) return ok(state.scriptSubdomain);
    if (endpoint === `${script}/secrets` && init.method === 'GET') return ok([...state.secrets.keys()].map(name => ({ name, type: 'secret_text' })));
    if (endpoint === `${script}/secrets` && init.method === 'PUT') { state.secrets.set(call.body.name, call.body.text); return ok({}); }
    if (endpoint === `${script}?force=true` && init.method === 'DELETE') {
      if (state.deleteRemoves) state.scripts = state.scripts.filter(id => id !== STAGING); return ok(null);
    }
    return new Response(JSON.stringify({ success: false, errors: [{ code: 10000 }] }), { status: 404 });
  };
  const cf = (readOnly = false) => new StagingCloudflare(oauth, undefined, fetchImpl, { readOnly });
  const stageWorker = async (stagedAccount, stagedOrigin) => {
    state.stageWorkerCalls++;
    assert.equal(stagedAccount, account); assert.equal(stagedOrigin, origin);
    state.scripts.push(STAGING);
    state.vars = stagingWorkerConfig('/fixture/repository', revision, stagedOrigin).vars;
    state.namespaces.push({ id: stagingNamespace, class: 'CoachAuthenticationState', script: STAGING, use_sqlite: true });
  };
  return { state, cf, stageWorker };
}
const deploy = (f, extra = {}) => { const reports = [];
  return { reports, run: deployStaging({ cf: f.cf(), credentials: { ...apple }, revision, stageWorker: f.stageWorker,
    probe: async () => {}, report: line => reports.push(line), ...extra }) }; };
const noProduction = state => assert.ok(state.calls.every(call =>
  !call.endpoint.includes(`/scripts/${TARGET.worker}`) && !call.endpoint.startsWith('/zones')));

test('staging configuration is a separate workers.dev script with labels, its own SQLite migration and no model key', () => {
  const config = stagingWorkerConfig('/fixture/repository', revision, origin);
  assert.equal(config.name, STAGING); assert.notEqual(config.name, TARGET.worker);
  assert.equal(config.workers_dev, true); assert.equal(config.preview_urls, false); assert.deepEqual(config.routes, []);
  assert.equal(config.observability.enabled, false); assert.equal(config.logpush, false);
  assert.deepEqual(config.vars, { COACH_AUTH_MODE: 'app-attest-storekit-v1', COACH_AUTH_SOURCE_REV: revision,
    COACH_STAGING_ORIGIN: origin, COACH_STAGING_LABELS: '1' });
  assert.deepEqual(config.migrations, [{ tag: 'coach-security-v1', new_sqlite_classes: ['CoachAuthenticationState'] }]);
  assert.ok(!JSON.stringify(config).includes('OPENAI') && !JSON.stringify(config).includes('coach.reptoday.app'));
  for (const bad of ['https://coach.reptoday.app/coach', `https://${STAGING}.x.workers.dev/other`, `http://${STAGING}.x.workers.dev/coach`])
    assert.throws(() => stagingWorkerConfig('/fixture/repository', revision, bad), stopped('subdomain'));
  assert.throws(() => stagingOrigin('Bad_Subdomain'), stopped('subdomain'));
});

test('deploy provisions only staging: fresh gate, five App Store items, exact verification and labelled probes', async () => {
  const f = fixture(); let probed = null;
  const { reports, run } = deploy(f, { probe: async value => { probed = value; } });
  await run;
  assert.deepEqual(reports, [stagingLines.confirmed, stagingLines.deployed(origin), stagingLines.verified]);
  assert.equal(probed, origin);
  assert.deepEqual([...f.state.secrets.keys()].sort(), [...STAGING_SECRET_NAMES].sort());
  assert.match(f.state.secrets.get('CLIENT_SHARED_SECRET'), /^[a-f0-9]{64}$/);
  assert.equal(f.state.secrets.get('APP_STORE_PRIVATE_KEY'), apple.privateKey);
  assert.ok(![...f.state.secrets.keys()].includes('OPENAI_API_KEY'));
  assert.ok(f.state.calls.every(call => call.authorization === `Bearer ${oauth}`));
  noProduction(f.state);
  // Two deploys never reuse a gate secret.
  const g = fixture(); await deploy(g).run;
  assert.notEqual(g.state.secrets.get('CLIENT_SHARED_SECRET'), f.state.secrets.get('CLIENT_SHARED_SECRET'));
});

test('deploy requires a fully torn-down staging name before any mutation', async () => {
  for (const [name, arrange] of [
    ['existing script with stale model secret', state => {
      state.scripts.push(STAGING); state.secrets.set('OPENAI_API_KEY', 'STALE-NONSECRET-FIXTURE');
    }],
    ['leftover namespace', state => state.namespaces.push({
      id: stagingNamespace, class: 'CoachAuthenticationState', script: STAGING, use_sqlite: true,
    })],
    ['leftover custom domain', state => state.domains.push({ hostname: 'staging.example', service: STAGING })],
  ]) {
    const f = fixture(); arrange(f.state);
    const secretsBefore = new Map(f.state.secrets);
    await assert.rejects(deploy(f).run, stopped('present'), name);
    assert.equal(f.state.stageWorkerCalls, 0, name);
    assert.deepEqual(f.state.secrets, secretsBefore, name);
    assert.equal(f.state.calls.some(call => call.method === 'PUT'), false, name);
    noProduction(f.state);
  }
});

test('deploy stops on any unsafe or unexpected staging shape', async () => {
  for (const [name, arrange, code] of [
    ['two accounts', s => s.accounts.push({ id: 'b'.repeat(32) }), 'account'],
    ['no workers.dev subdomain', s => { s.subdomain = { subdomain: null }; }, 'subdomain'],
    ['model key binding', s => s.extraBindings.push({ name: 'OPENAI_API_KEY', type: 'secret_text' }), 'settings'],
    ['namespace shared with production', s => { s.namespaces[0].id = stagingNamespace; }, 'namespace'],
    ['workers.dev disabled', s => { s.scriptSubdomain = { enabled: false }; }, 'subdomain'],
  ]) {
    const f = fixture(); arrange(f.state);
    await assert.rejects(deploy(f).run, stopped(code), name);
    noProduction(f.state);
  }
  const f = fixture();
  await assert.rejects(deploy(f, { probe: async () => { throw new DeploymentFailure('probe'); } }).run, stopped('probe'));
  await assert.rejects(deployStaging({ cf: fixture().cf(), credentials: { ...apple, openAI: 'x' }, revision,
    stageWorker: async () => {}, probe: async () => {} }), stopped('input'));
  await assert.rejects(deployStaging({ cf: fixture().cf(), credentials: { ...apple }, revision: 'HEAD',
    stageWorker: async () => {}, probe: async () => {} }), stopped('revision'));
});

test('the staging client cannot address production, zones, model secrets or mutate when read-only', async () => {
  const f = fixture(); const cf = f.cf(); cf.account = account;
  const production = `/accounts/${account}/workers/scripts/${TARGET.worker}`, script = `/accounts/${account}/workers/scripts/${STAGING}`;
  for (const [endpoint, method, body] of [
    [`${production}/settings`, 'GET'], [`${production}/secrets`, 'PUT', { name: 'APP_STORE_KEY_ID', type: 'secret_text', text: 'x' }],
    [`${production}?force=true`, 'DELETE'], ['/zones', 'GET'], [`${script}/secrets`, 'PUT', { name: 'OPENAI_API_KEY', type: 'secret_text', text: 'x' }],
    [`${script}`, 'DELETE'], [`${script}/settings`, 'PATCH', {}],
  ]) await assert.rejects(cf.accountRequest(endpoint, method, body), stopped('scope'), endpoint);
  const readOnly = f.cf(true); readOnly.account = account;
  await assert.rejects(readOnly.accountRequest(`${script}?force=true`, 'DELETE'), stopped('scope'));
  assert.equal(f.state.calls.length, 0);
});

test('teardown force-deletes only staging and confirms production is untouched', async () => {
  const f = fixture(); await deploy(f).run; f.state.calls.length = 0;
  const reports = []; await teardownStaging({ cf: f.cf(), report: line => reports.push(line) });
  assert.deepEqual(reports, [stagingLines.removed]);
  assert.deepEqual(f.state.calls.filter(call => call.method === 'DELETE').map(call => call.endpoint),
    [`/accounts/${account}/workers/scripts/${STAGING}?force=true`]);
  assert.ok(f.state.scripts.includes(TARGET.worker)); noProduction(f.state);
  const again = []; await teardownStaging({ cf: f.cf(), report: line => again.push(line) });
  assert.deepEqual(again, [stagingLines.absent]);
  const stuck = fixture(); await deploy(stuck).run; stuck.state.deleteRemoves = false;
  await assert.rejects(teardownStaging({ cf: stuck.cf() }), stopped('teardown'));
});

test('inspect is read-only and reports absent or a verified staging Worker', async () => {
  const f = fixture(); const reports = [];
  await inspectStaging({ cf: f.cf(true), report: line => reports.push(line) });
  await deploy(f).run; f.state.calls.length = 0;
  await inspectStaging({ cf: f.cf(true), report: line => reports.push(line) });
  assert.deepEqual(reports, [stagingLines.absent, stagingLines.inspected(origin)]);
  assert.ok(f.state.calls.every(call => call.method === 'GET'));
});

test('staging probes require the exact labelled denial and only the first may wait for a new workers.dev route', async () => {
  const clock = () => { let t = 0; const waits = []; return { now: () => t, wait: async ms => { waits.push(ms); t += ms; }, waits }; };
  const answer = (options, label) => new Response('{"error":"unauthorized"}', { status: 401,
    headers: { 'X-RepToday-Coach-Diagnostic': label ?? (options.headers['X-RepToday-Coach-Auth'] ? 'worker_envelope/proof_envelope' : 'worker_envelope/missing_proof') } });
  let c = clock(), requests = [];
  await stagingProbes(origin, async (url, options) => { requests.push([url, options.body]); return answer(options); }, c);
  assert.deepEqual(requests, [[origin, '{}'], [origin, '{}']]); assert.deepEqual(c.waits, []);
  c = clock(); let first = 0;
  await stagingProbes(origin, async (url, options) => options.headers['X-RepToday-Coach-Auth'] || ++first > 2 ? answer(options) :
    new Response('not found', { status: 404 }), c);
  assert.deepEqual(c.waits, [5000, 5000]);
  for (const [name, impl] of [
    ['wrong label', async options => answer(options, 'worker_state/denied')],
    ['missing label', async () => new Response('{"error":"unauthorized"}', { status: 401 })],
    ['extra body', async options => new Response('{"error":"unauthorized","x":1}', { status: 401, headers: answer(options).headers })],
    ['second probe unavailable', async options => options.headers['X-RepToday-Coach-Auth'] ? new Response('', { status: 503 }) : answer(options)],
  ]) {
    c = clock();
    await assert.rejects(stagingProbes(origin, async (url, options) => impl(options), c), stopped('probe'), name);
    if (name !== 'second probe unavailable') assert.deepEqual(c.waits, [], name);
  }
  c = clock();
  await assert.rejects(stagingProbes(origin, async () => new Response('', { status: 404 }), c), stopped('probe'));
  assert.equal(c.waits.length, 5);
});

test('failure output is one closed stop code', () => {
  assert.equal(stagingFailureOutput(new DeploymentFailure('domain')), 'blocked: domain\n');
  assert.equal(stagingFailureOutput(new DeploymentFailure('present')), 'blocked: present\n');
  assert.equal(stagingFailureOutput(new DeploymentFailure('NONSECRET')), 'blocked: unexpected\n');
  assert.equal(stagingFailureOutput(new Error('NONSECRET')), 'blocked: unexpected\n');
});
