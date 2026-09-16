import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { RuntimeCloudflare, runtimePacket, runtimeConfig, checkRuntimeSettings, migrateRuntime,
  runtimeGateProbes, runtimeLines, runtimeSecretNames } from './coach-runtime-migrate.mjs';
import { DeploymentFailure, TARGET, HOLD, BOUNDARY, LIMIT, CUSTOM, RATE, checkSettings } from './coach-production-deploy.mjs';

// No production entries, auth files, Keychain or network are touched by these doubles.
const account = 'a'.repeat(32), zone = 'b'.repeat(32), namespace = 'c'.repeat(32), revision = 'd'.repeat(40);
const oldRevision = 'e'.repeat(40), oauth = 'NONSECRET_OAUTH_TEST_DOUBLE';
const privateKey = generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).privateKey.export({ type: 'pkcs8', format: 'pem' });
const credentials = { openAI: 'sk-NONSECRET_PROVIDER_TEST_DOUBLE_123', clientGate: '0'.repeat(64),
  wafToken: 'NONSECRET_WAF_TOKEN_TEST_DOUBLE_123', appPrefix: 'FIXTURE001', appID: '123456', keyID: 'FIXTURE002',
  issuerID: '00000000-0000-0000-0000-000000000000', privateKey };
const worker = `/accounts/${account}/workers/scripts/${TARGET.worker}`;
const stopped = code => error => error instanceof DeploymentFailure && error.code === code;
function settings(rev = revision) {
  return { bindings: [{ name: 'COACH_AUTH_MODE', type: 'plain_text', text: 'app-attest-storekit-v1' },
    { name: 'COACH_AUTH_SOURCE_REV', type: 'plain_text', text: rev },
    { name: 'COACH_AUTH_STATE', type: 'durable_object_namespace', class_name: 'CoachAuthenticationState', namespace_id: namespace }],
    observability: { enabled: false }, logpush: false, tail_consumers: [] };
}
function fixture({ runtime = false } = {}) {
  const state = { settings: runtime ? settings() : { bindings: [{ name: 'ANTHROPIC_MODEL', type: 'plain_text', text: 'claude-opus-4-8' }], logpush: false },
    scripts: [{ id: TARGET.worker, ...(runtime ? { migration_tag: 'coach-security-v1' } : {}) }],
    domains: [{ hostname: TARGET.hostname, service: TARGET.worker, zone_id: zone, environment: 'production' }], routes: [],
    namespaces: runtime ? [{ id: namespace, class: 'CoachAuthenticationState', script: TARGET.worker, use_sqlite: true }] : [],
    subdomain: { enabled: false, previews_enabled: false }, calls: [], reports: [], stages: 0, probes: 0,
    accounts: [{ id: account }], zones: [{ id: zone, name: TARGET.zone, status: 'active', account: { id: account }, plan: { name: 'Free Website' } }],
    custom: { id: '1'.repeat(32), kind: 'zone', phase: CUSTOM,
      rules: [{ ...HOLD, id: '2'.repeat(32), enabled: false }, { ...BOUNDARY, id: '3'.repeat(32) }] },
    rate: { id: '4'.repeat(32), kind: 'zone', phase: RATE, rules: [{ ...structuredClone(LIMIT), id: '5'.repeat(32) }] },
    fail: null };
  for (const name of runtime ? runtimeSecretNames : ['OPENAI_API_KEY', 'CLIENT_SHARED_SECRET']) state.settings.bindings.push({ name, type: 'secret_text' });
  const fetchImpl = async (url, options) => {
    assert.equal(url.origin, 'https://api.cloudflare.com'); assert.equal(options.redirect, 'error'); assert.ok(options.signal);
    const endpoint = url.pathname.slice('/client/v4'.length) + url.search;
    const body = options.body ? JSON.parse(options.body) : undefined;
    const call = { endpoint, method: options.method, body, authorization: options.headers.Authorization }; state.calls.push(call);
    if (state.fail?.(call)) return new Response('{"success":false}', { status: 403 });
    let result;
    if (endpoint.startsWith(`/zones/${zone}/rulesets/`)) {
      assert.equal(call.authorization, `Bearer ${credentials.wafToken}`);
      if (options.method === 'GET') {
        if (endpoint.includes(`/phases/${CUSTOM}/`)) result = state.custom;
        else if (endpoint.includes(`/phases/${RATE}/`)) result = state.rate;
        else assert.fail('Unapproved zone read');
      } else {
        assert.equal(options.method, 'PATCH'); assert.equal(endpoint, `/zones/${zone}/rulesets/${state.custom.id}/rules/${state.custom.rules[0].id}`);
        Object.assign(state.custom.rules[0], body); result = state.custom;
      }
    } else {
      assert.equal(call.authorization, `Bearer ${oauth}`);
      if (endpoint === '/accounts') result = state.accounts;
      else if (endpoint.startsWith('/zones?')) result = state.zones;
      else if (endpoint === `/accounts/${account}/workers/scripts`) result = state.scripts;
      else if (endpoint === `/accounts/${account}/workers/domains`) result = state.domains;
      else if (endpoint === `/zones/${zone}/workers/routes`) result = state.routes;
      else if (endpoint === `/accounts/${account}/workers/durable_objects/namespaces`) result = state.namespaces;
      else if (endpoint === worker + '/settings') result = state.settings;
      else if (endpoint === worker + '/subdomain') result = state.subdomain;
      else if (endpoint === worker + '/secrets') {
        if (options.method === 'PUT') { assert.ok(!state.settings.bindings.some(item => item.name === body.name)); state.settings.bindings.push({ name: body.name, type: body.type }); }
        result = state.settings.bindings.filter(item => item.type === 'secret_text').map(({ name, type }) => ({ name, type }));
      } else assert.fail('Unapproved account operation');
    }
    return new Response(JSON.stringify({ success: true, result }));
  };
  const cf = new RuntimeCloudflare(oauth, credentials.wafToken, fetchImpl);
  const held = () => state.custom.rules[0].enabled;
  const stageWorker = async selected => {
    assert.equal(selected, account); assert.equal(held(), true); state.stages++;
    const secrets = state.settings.bindings.filter(item => item.type === 'secret_text');
    state.settings = settings(); state.settings.bindings.push(...secrets);
    state.scripts[0].migration_tag = 'coach-security-v1';
    state.namespaces = [{ id: namespace, class: 'CoachAuthenticationState', script: TARGET.worker, use_sqlite: true }];
  };
  const run = (operation, overrides = {}) => migrateRuntime({ cf, operation, revision,
    credentials: operation === '--stage' ? credentials : operation === '--release' ?
      { clientGate: credentials.clientGate, wafToken: credentials.wafToken } : { wafToken: credentials.wafToken },
    stageWorker, probe: async gate => { assert.equal(gate, credentials.clientGate); assert.equal(held(), false); state.probes++; },
    report: line => state.reports.push(line), ...overrides });
  return { state, cf, run, held, stageWorker };
}
const writes = state => state.calls.filter(call => call.method !== 'GET');

test('stage first holds existing origin, provisions only five missing server bindings and never releases or probes', async () => {
  const { state, run, held } = fixture(); await run('--stage');
  assert.equal(held(), true); assert.equal(state.stages, 1); assert.equal(state.probes, 0);
  assert.deepEqual(state.reports, [runtimeLines.confirmed, runtimeLines.protected, runtimeLines.staged]);
  assert.equal(writes(state)[0].body.ref, HOLD.ref); assert.equal(writes(state)[0].body.enabled, true);
  assert.deepEqual(writes(state).filter(call => call.method === 'PUT').map(call => call.body.name).sort(), runtimeSecretNames.filter(name => !['OPENAI_API_KEY','CLIENT_SHARED_SECRET'].includes(name)).sort());
  assert.ok(writes(state).every(call => call.endpoint.endsWith('/secrets') || call.endpoint.includes('/rules/')));
  assert.ok(state.reports.every(line => ![account, zone, namespace, oauth, ...Object.values(credentials)].some(value => line.includes(value))));
});
test('stage preserves existing server secrets and namespace on a repeated reviewed migration', async () => {
  const { state, run, held } = fixture({ runtime: true }); state.settings.bindings.find(item => item.name === 'COACH_AUTH_SOURCE_REV').text = oldRevision;
  await run('--stage'); assert.equal(held(), true); assert.equal(writes(state).filter(call => call.method === 'PUT').length, 0);
});
test('release verifies committed source, all bindings, SQLite migration and protection before bounded no-model probes', async () => {
  const { state, run, held } = fixture({ runtime: true }); await run('--release');
  assert.equal(held(), false); assert.equal(state.stages, 0); assert.equal(state.probes, 1);
  assert.deepEqual(state.reports, [runtimeLines.confirmed, runtimeLines.protected, runtimeLines.released]);
  assert.ok(writes(state).every(call => call.method === 'PATCH' && call.body.ref === HOLD.ref));
});
test('hold-only rollback ignores invalid Worker configuration, preserves all records and never uploads/deploys/probes', async () => {
  const { state, run, held } = fixture({ runtime: true }); state.settings = null; await run('--hold');
  assert.equal(held(), true); assert.equal(state.stages, 0); assert.equal(state.probes, 0);
  assert.deepEqual(state.reports, [runtimeLines.confirmed, runtimeLines.held]); assert.equal(writes(state).length, 1);
  assert.ok(state.calls.every(call => !call.endpoint.endsWith('/settings') && !call.endpoint.endsWith('/secrets') && !call.endpoint.endsWith('/namespaces')));
});
for (const [name, change, code] of [
  ['ambiguous account', s => s.accounts.push({ id: 'f'.repeat(32) }), 'account'],
  ['wrong zone', s => s.zones[0].name = 'foreign.invalid', 'zone'],
  ['changed plan', s => s.zones[0].plan.name = 'Paid', 'rate-plan'],
  ['absent Worker', s => s.scripts = [], 'target'],
  ['absent attached domain', s => s.domains = [], 'route'],
  ['foreign attached domain', s => s.domains[0].service = 'foreign', 'route'],
  ['wildcard legacy route', s => s.routes = [{ pattern: '*.reptoday.app/*', script: 'foreign' }], 'route'],
  ['missing hold', s => s.custom.rules.shift(), 'rules'],
  ['missing boundary', s => s.custom.rules.pop(), 'rules'],
  ['disabled rate', s => s.rate.rules[0].enabled = false, 'rules'],
  ['missing operator gate', s => s.settings.bindings = s.settings.bindings.filter(item => item.name !== 'CLIENT_SHARED_SECRET'), 'secret'],
  ['unexpected persistence on legacy', s => s.settings.bindings.push({ name: 'UNAPPROVED', type: 'kv_namespace' }), 'settings'],
]) test('preflight stops without mutation: ' + name, async () => {
  const { state, run } = fixture(); change(state); await assert.rejects(run('--stage'), stopped(code));
  assert.equal(writes(state).length, 0); assert.equal(state.stages, 0); assert.equal(state.probes, 0);
});
for (const [name, change, code] of [
  ['logging', s => s.settings.observability.enabled = true, 'settings'],
  ['tail', s => s.settings.tail_consumers = [{}], 'settings'],
  ['nested logging', s => s.settings.observability.logs = { enabled: true }, 'settings'],
  ['development URLs', s => s.subdomain.enabled = true, 'settings'],
  ['preview URLs', s => s.subdomain.previews_enabled = true, 'settings'],
  ['foreign namespace class', s => s.namespaces[0].class = 'Foreign', 'namespace'],
  ['legacy KV backend', s => s.namespaces[0].use_sqlite = false, 'namespace'],
  ['omitted SQLite confirmation', s => delete s.namespaces[0].use_sqlite, 'namespace'],
  ['migration mismatch', s => s.scripts[0].migration_tag = 'foreign', 'namespace'],
  ['missing Apple binding', s => s.settings.bindings = s.settings.bindings.filter(item => item.name !== 'APP_STORE_PRIVATE_KEY'), 'secret'],
  ['different reviewed source', s => s.settings.bindings.find(item => item.name === 'COACH_AUTH_SOURCE_REV').text = oldRevision, 'revision'],
]) test('release refuses ' + name + ' before any hold release/probe', async () => {
  const { state, run } = fixture({ runtime: true }); change(state); await assert.rejects(run('--release'), stopped(code));
  assert.equal(writes(state).length, 0); assert.equal(state.probes, 0);
});
test('stage failure leaves verified hold closed and never provisions or releases', async () => {
  const { state, run, held } = fixture(); await assert.rejects(run('--stage', { stageWorker: async () => { throw new DeploymentFailure('wrangler'); } }), stopped('wrangler'));
  assert.equal(held(), true); assert.equal(writes(state).filter(call => call.method === 'PUT').length, 0);
});
test('post-stage namespace/settings failure leaves hold closed before secret upload', async () => {
  const { state, run, held, stageWorker } = fixture(); await assert.rejects(run('--stage', { stageWorker: async selected => { await stageWorker(selected); state.namespaces[0].use_sqlite = false; } }), stopped('namespace'));
  assert.equal(held(), true); assert.equal(writes(state).filter(call => call.method === 'PUT').length, 0);
});
test('secret provisioning failure leaves hold closed, without rotation or public probes', async () => {
  const { state, run, held } = fixture(); state.fail = call => call.method === 'PUT';
  await assert.rejects(run('--stage'), stopped('http')); assert.equal(held(), true); assert.equal(state.probes, 0);
});
test('failed public denial probe immediately re-holds and never reports release success', async () => {
  const { state, run, held } = fixture({ runtime: true }); await assert.rejects(run('--release', { probe: async () => { throw new DeploymentFailure('gate'); } }), stopped('gate'));
  assert.equal(held(), true); assert.ok(!state.reports.includes(runtimeLines.released));
});
test('failure to re-hold is a distinct actionable stop, with no success output', async () => {
  const { state, run } = fixture({ runtime: true }); await assert.rejects(run('--release', { probe: async () => {
    state.fail = call => call.method === 'PATCH' && call.body.enabled === true; throw new DeploymentFailure('gate');
  } }), stopped('rehold')); assert.ok(!state.reports.includes(runtimeLines.released));
});
test('runtime transport refuses DNS/domain writes, foreign secret names and namespace scope before fetch', async () => {
  let calls = 0; const cf = new RuntimeCloudflare(oauth, credentials.wafToken, async () => { calls++; throw Error('forbidden'); }); cf.setScope(account, zone);
  for (const [endpoint, method, body] of [[worker + '/domains/records','PUT',{}], [worker + '/domains/changeset?replace_state=true','POST',[]],
    [worker + '/secrets','DELETE',{}], [`/accounts/${zone}/workers/durable_objects/namespaces`,'GET',undefined]]) {
    await assert.rejects(cf.accountRequest(endpoint, method, body), stopped('scope'));
  }
  await assert.rejects(cf.accountRequest(worker + '/secrets','PUT',{name:'FOREIGN',type:'secret_text',text:'fixture'}),stopped('secret')); assert.equal(calls,0);
});
test('runtime settings require unique approved bindings, correct namespace, source and strict disabled logging', () => {
  const good = settings(); assert.equal(checkRuntimeSettings(good, revision), namespace);
  for (const binding of [{name:'COACH_AUTH_STATE',type:'durable_object_namespace',class_name:'Foreign',namespace_id:namespace},
    {name:'COACH_AUTH_STATE',type:'durable_object_namespace',class_name:'CoachAuthenticationState',namespace_id:namespace,script_name:'foreign'},
    {name:'COACH_AUTH_STATE',type:'durable_object_namespace',class_name:'CoachAuthenticationState',namespace_id:namespace,environment:'staging'},
    {name:'FOREIGN',type:'secret_text'},good.bindings[0]]) {
    const altered=structuredClone(good);altered.bindings.push(binding);assert.throws(()=>checkRuntimeSettings(altered,revision),DeploymentFailure);
  }
  for (const change of [s=>s.logpush=null,s=>s.tail_consumers={},s=>s.observability=null]) {
    const altered=structuredClone(good);change(altered);assert.throws(()=>checkRuntimeSettings(altered,revision),DeploymentFailure);
  }
  assert.throws(()=>checkSettings(good),stopped('settings')); // Legacy persistence rejection remains intact.
});
test('operation packets restrict credential reads; invalid identifiers/key types fail without exposing values', () => {
  assert.equal(runtimePacket(credentials,'--stage'),credentials);
  assert.throws(()=>runtimePacket(credentials,'--hold'),stopped('input'));
  assert.throws(()=>runtimePacket(credentials,'--release'),stopped('input'));
  for (const change of [p=>p.appID='9007199254740992',p=>p.issuerID='foreign',p=>p.appPrefix='bad',p=>p.privateKey='bad',
    p=>p.privateKey=generateKeyPairSync('rsa',{modulusLength:2048}).privateKey.export({type:'pkcs8',format:'pem'})]) {
    const altered={...credentials};change(altered);assert.throws(()=>runtimePacket(altered,'--stage'),stopped('input'));
  }
});
test('generated migration configuration contains public source only and exclusively a SQLite create migration', () => {
  const config=runtimeConfig('/fixture/repository',revision); const serialized=JSON.stringify(config);
  assert.ok(![account,zone,namespace,oauth,...Object.values(credentials)].some(value=>serialized.includes(value)));
  assert.deepEqual(config.migrations,[{tag:'coach-security-v1',new_sqlite_classes:['CoachAuthenticationState']}]);
  assert.equal(config.vars.COACH_AUTH_SOURCE_REV,revision);assert.equal(config.routes.length,0);
  assert.equal(config.workers_dev,false);assert.equal(config.preview_urls,false);assert.equal(config.observability.enabled,false);
});
test('release probe uses only malformed/non-identifying inputs and rejects forged proof before any model path', async () => {
  const requests=[];
  await runtimeGateProbes(credentials.clientGate,async(url,options)=>{
    assert.equal(url,TARGET.origin);assert.equal(options.redirect,'error');requests.push(options);
    const valid=options.headers.Authorization === 'Bearer '+credentials.clientGate;
    return new Response(JSON.stringify({error:valid?'invalid_request':'unauthorized'}),{status:valid?400:401});
  });
  assert.equal(requests.length,4);assert.deepEqual(requests.map(item=>item.body),['{','{','{','{}']);
  await assert.rejects(runtimeGateProbes(credentials.clientGate,async(url,options)=>{
    const forged=options.headers['X-RepToday-Coach-Auth'];const valid=options.headers.Authorization === 'Bearer '+credentials.clientGate;
    return new Response(JSON.stringify({error:forged?'auth_unavailable':'unauthorized'}),{status:forged?503:valid?400:401});
  }),stopped('gate'));
});
