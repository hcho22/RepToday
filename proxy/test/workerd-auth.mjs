import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { builtinModules } from 'node:module';
import { generateKeyPairSync, verify } from 'node:crypto';
import { build } from 'esbuild';
import { Miniflare } from 'miniflare';
import { fixtureKey, signedAssertion, APP_PREFIX, TEST_GATE, TEST_BODY_HASH, TEST_TRANSACTION_HASH } from './auth-fixtures.js';
import { VERSION, ORIGIN, hash, challengeToken, assertionPayload } from '../src/coach-auth-crypto.js';

const root = resolve('..');
const output = resolve('../build/coach-runtime-auth');
await mkdir(output, {recursive: true});
await writeFile(resolve(output, 'node-globals.mjs'), 'import {Buffer} from "node:buffer"; import process from "node:process"; export {Buffer,process};');
// Matches Wrangler 3.114.17 handleRequireCallsToNodeJSBuiltins. Generic esbuild externalization
// produces unsupported dynamic require; production Wrangler's nodejs_compat plugin supplies these.
const nativeRequire = {name: 'wrangler-native-require-equivalence', setup(b) {
  b.onResolve({filter: /^(node:)?[a-z_]+(?:\/[a-z_]+)?$/}, a => {
    if (a.kind === 'require-call' && (builtinModules.includes(a.path) || a.path.startsWith('node:')))
      return {path: a.path, namespace: 'native-require'};
  });
  b.onLoad({filter: /.*/, namespace: 'native-require'}, a => ({loader: 'js',
    contents: `import native from ${JSON.stringify(a.path.startsWith('node:') ? a.path : 'node:' + a.path)}; module.exports=native;`}));
}};
const options = {bundle: true, format: 'esm', platform: 'node', target: 'es2023',
  alias: {'node-fetch': resolve('src/apple-fetch.js')}, external: ['cloudflare:workers', ...builtinModules, ...builtinModules.map(x => 'node:' + x)],
  inject: [resolve(output, 'node-globals.mjs')], plugins: [nativeRequire]};
await build({...options, entryPoints: ['src/coach-auth-worker.js'], outfile: resolve(output, 'gateway-compatible.mjs')});
await build({...options, entryPoints: ['test/workerd-auth-entry.js'], outfile: resolve(output, 'runtime-tests.mjs')});
let localAppleCalls = 0;
const key = fixtureKey();
const apiKey = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
const m = new Miniflare({modulesRoot: root, scriptPath: resolve(output, 'runtime-tests.mjs'), modules: true,
  compatibilityDate: '2025-07-18', compatibilityFlags: ['nodejs_compat'],
  durableObjects: {COACH_AUTH_STATE: {className: 'FixtureAuthenticationState', useSQLite: true}},
  bindings: {COACH_AUTH_MODE: 'app-attest-storekit-v1', CLIENT_SHARED_SECRET: TEST_GATE, APP_ATTEST_APP_PREFIX: APP_PREFIX,
    APP_STORE_APP_ID: '1', APP_STORE_KEY_ID: APP_PREFIX, APP_STORE_ISSUER_ID: '00000000-0000-4000-8000-000000000000',
    APP_STORE_PRIVATE_KEY: 'TEST-ONLY-INVALID-KEY-NO-APPLE-AUTHORITY'},
  outboundService: request => {
    // A local service double; never fetches the network. Inspect only generated test JWTs in memory.
    const url = new URL(request.url);
    assert.equal(url.origin, 'https://api.storekit.apple.com');
    assert.equal(url.pathname, '/inApps/v1/subscriptions/123'); assert.equal(url.search, '');
    assert.equal(request.method, 'GET');
    const parts = request.headers.get('Authorization').slice(7).split('.');
    const header = JSON.parse(Buffer.from(parts[0], 'base64url'));
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url'));
    assert.equal(header.alg, 'ES256'); assert.equal(header.kid, APP_PREFIX);
    assert.equal(payload.bid, 'com.reptoday.app'); assert.equal(payload.aud, 'appstoreconnect-v1');
    assert.ok(verify('sha256', Buffer.from(parts.slice(0,2).join('.')),
      {key:apiKey.publicKey,dsaEncoding:'ieee-p1363'}, Buffer.from(parts[2],'base64url')));
    localAppleCalls++;
    return new Response(JSON.stringify({environment:'Production',bundleId:'com.reptoday.app',appAppleId:1,data:[]}));
  }});
const call = (url, input, headers = {}) => m.dispatchFetch(url, {method: 'POST', headers, body: JSON.stringify(input)});
try {
  assert.equal((await call(ORIGIN, {})).status, 401);
  const payload = assertionPayload('reply', key.keyId, 'fixture', TEST_BODY_HASH, TEST_TRANSACTION_HASH);
  const assertion = signedAssertion(key, payload);
  assert.equal((await call('https://runtime-fixture.invalid/', {operation:'assert', assertion: assertion.toString('base64'),
    publicKey: key.publicKey, previousCounter: 0, payload: payload.toString('base64'), prefix: APP_PREFIX})).status, 200);
  assert.equal((await call('https://runtime-fixture.invalid/', {operation:'assert', assertion: assertion.toString('base64'),
    publicKey: key.publicKey, previousCounter: 1, payload: payload.toString('base64'), prefix: APP_PREFIX})).status, 401);
  assert.equal((await call('https://runtime-fixture.invalid/', {operation:'premium', jws:'a.b.c'})).status, 401);
  assert.equal(localAppleCalls,0);
  const apiResult = await call('https://runtime-fixture.invalid/', {operation:'apple-api',
    privateKey:apiKey.privateKey.export({type:'pkcs8',format:'pem'})});
  assert.equal(apiResult.status,200,await apiResult.text());
  assert.equal(localAppleCalls,1);
  assert.equal((await call('https://runtime-fixture.invalid/', {operation:'attest', keyId:key.keyId, attestation:'AA==', challenge:'fixture',prefix:APP_PREFIX})).status, 401);
  const ns = await m.getDurableObjectNamespace('COACH_AUTH_STATE');
  const id = ns.idFromName(VERSION + ':' + hash(key.keyId));
  const stub=ns.get(id);
  await stub.fetch('https://fixture-seed.invalid/', {method:'POST', body:JSON.stringify({v:VERSION, publicKey:key.publicKey, counter:0, expiresAt:Date.now()+60000})});
  const result = await call(ORIGIN, {operation:'challenge',kind:'assert',keyId:key.keyId});
  assert.equal(result.status,200); const {challenge}=await result.json();
  const signed=signedAssertion(key,assertionPayload('reply',key.keyId,challenge,TEST_BODY_HASH,TEST_TRANSACTION_HASH));
  const input={operation:'reply',keyId:key.keyId,challenge,assertion:signed.toString('base64'),bodyHash:TEST_BODY_HASH,transactionHash:TEST_TRANSACTION_HASH};
  const execute=()=>stub.fetch('https://security.invalid/',{method:'POST',body:JSON.stringify(input)});
  const simultaneous=await Promise.all([execute(),execute()]);
  assert.deepEqual(simultaneous.map(r=>r.status).sort(),[200,401]);
  const record=await (await stub.fetch('https://fixture-record.invalid/')).json();
  assert.equal(record.counter,1);
  assert.deepEqual(Object.keys(record).sort(),['counter','expiresAt','publicKey','v']);
  assert.equal(localAppleCalls,1);
  console.log('validated: installed workerd native crypto, Apple verifier negatives, official API JWT/transport local double and SQLite atomic replay; zero external requests');
} finally {await m.dispose();}
