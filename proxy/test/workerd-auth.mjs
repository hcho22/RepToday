import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { builtinModules } from 'node:module';
import { generateKeyPairSync, verify } from 'node:crypto';
import { build } from 'esbuild';
import { Miniflare, Response as MiniflareResponse } from 'miniflare';
import {appleApiFixture} from './apple-api-probe.js';
import {pathToFileURL} from 'node:url';
import { fixtureKey, signedAssertion, APP_PREFIX, TEST_GATE, TEST_BODY_HASH, TEST_TRANSACTION_HASH } from './auth-fixtures.js';
import { VERSION, ORIGIN, hash, assertionPayload } from '../src/coach-auth-crypto.js';

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
await build({...options, entryPoints: ['test/apple-api-probe.js'], outfile: resolve(output, 'node-api-probe.mjs')});
let localAppleCalls = 0;
let localResponseCalls = 0;
let fixtureResponse = Response;
let fixtureStatus = 200;
const key = fixtureKey();
const apiKey = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
let rejectedLocalCalls = 0;
const localAppleFixture = request => {
  try {
    // A local service double; never fetches the network. Inspect only generated test JWTs in memory.
    const url = new URL(request.url);
    assert.equal(url.origin, 'https://api.storekit.apple.com');
    assert.equal(url.pathname, '/inApps/v1/subscriptions/123'); assert.equal(url.search, '');
    assert.equal(request.method, 'GET');
    if (request.headers.get('X-Local-Fixture') === 'response-only') {
      localResponseCalls++;
      return new fixtureResponse(JSON.stringify(appleApiFixture));
    }
    const parts = request.headers.get('Authorization').slice(7).split('.');
    const header = JSON.parse(Buffer.from(parts[0], 'base64url'));
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url'));
    assert.equal(header.alg, 'ES256'); assert.equal(header.kid, APP_PREFIX);
    assert.equal(payload.bid, 'com.reptoday.app'); assert.equal(payload.aud, 'appstoreconnect-v1');
    assert.ok(verify('sha256', Buffer.from(parts.slice(0,2).join('.')),
      {key:apiKey.publicKey,dsaEncoding:'ieee-p1363'}, Buffer.from(parts[2],'base64url')));
    localAppleCalls++;
    return new fixtureResponse(JSON.stringify(appleApiFixture), {status:fixtureStatus,
      headers:fixtureStatus === 302 ? {Location:'https://attacker.invalid/'} : {}});
  } catch {
    rejectedLocalCalls++;
    return new fixtureResponse("local-fixture-rejected", {status:500});
  }
};
const m = new Miniflare({modulesRoot: root, scriptPath: resolve(output, 'runtime-tests.mjs'), modules: true,
  compatibilityDate: '2025-07-18', compatibilityFlags: ['nodejs_compat'],
  durableObjects: {COACH_AUTH_STATE: {className: 'FixtureAuthenticationState', useSQLite: true}},
  bindings: {COACH_AUTH_MODE: 'app-attest-storekit-v1', CLIENT_SHARED_SECRET: TEST_GATE, APP_ATTEST_APP_PREFIX: APP_PREFIX,
    APP_STORE_APP_ID: '1', APP_STORE_KEY_ID: APP_PREFIX, APP_STORE_ISSUER_ID: '00000000-0000-4000-8000-000000000000',
    APP_STORE_PRIVATE_KEY: 'TEST-ONLY-INVALID-KEY-NO-APPLE-AUTHORITY'},
  outboundService: localAppleFixture});
const call = (url, input, headers = {}) => m.dispatchFetch(url, {method: 'POST', headers, body: JSON.stringify(input)});
try {
  if (process.argv.includes('--diagnose-apple-api')) {
    const env = {APP_STORE_KEY_ID: APP_PREFIX, APP_STORE_ISSUER_ID: '00000000-0000-4000-8000-000000000000'};
    const privateKey = apiKey.privateKey.export({type:'pkcs8',format:'pem'});
    const {probeAppleAPI, probeAppleRequest} = await import(pathToFileURL(resolve(output, 'node-api-probe.mjs')));
    const originalFetch = globalThis.fetch;
    // Same bounded production adapter and generated JWT; hard local stub cannot reach a network.
    globalThis.fetch = async (input, init) => localAppleFixture(new Request(input, init));
    try {
      const nodeSDK = await probeAppleAPI(privateKey, env, false, true);
      assert.equal(nodeSDK.ok,true,nodeSDK.phase);
      console.log('diagnostic: Node SDK ' + JSON.stringify(nodeSDK));
      const nodeRequests = await probeAppleRequest();
      assert.ok(nodeRequests.every(result=>result.ok));
      console.log('diagnostic: Node request options ' + JSON.stringify(nodeRequests));
      assert.equal(localAppleCalls,1);assert.equal(localResponseCalls,7);
      localAppleCalls=0;localResponseCalls=0;
    }
    finally {globalThis.fetch = originalFetch;}
    for (const [label, responseClass] of [['NodeResponse', Response], ['MiniflareResponse', MiniflareResponse]]) {
      fixtureResponse = responseClass;
      const before = localAppleCalls;
      const minimal = await call('https://runtime-fixture.invalid/', {operation:'apple-response',diagnose:true});
      const responseObservation = await minimal.json();
      assert.equal(responseObservation.ok,true,responseObservation.phase);
      console.log('diagnostic: workerd ' + label + ' response ' + JSON.stringify(responseObservation));
      const result = await call('https://runtime-fixture.invalid/', {operation:'apple-api', privateKey,diagnose:true});
      const sdkObservation = await result.json();
      assert.equal(sdkObservation.ok,true,sdkObservation.phase);
      assert.equal(localAppleCalls-before,1);
      console.log('diagnostic: workerd ' + label + ' SDK ' + JSON.stringify(sdkObservation) +
        ' service-dispatches=' + (localAppleCalls-before));
    }
    const workerRequests = await (await call('https://runtime-fixture.invalid/', {operation:'apple-request'})).json();
    assert.deepEqual(workerRequests.filter(result=>!result.ok).map(result=>result.variant),['redirect-error','full']);
    assert.ok(workerRequests.filter(result=>!result.ok).every(result=>result.phase==='request-construction'));
    console.log('diagnostic: workerd request options ' + JSON.stringify(workerRequests));
    assert.equal(localResponseCalls,7);
    assert.equal(rejectedLocalCalls,0);
  } else {
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
    const apiObservation = await apiResult.json();
    assert.equal(apiResult.status,200,apiObservation.phase);
    assert.equal(localAppleCalls,1);
    fixtureStatus = 302;
    const redirectResult = await call('https://runtime-fixture.invalid/', {operation:'apple-api',
      privateKey:apiKey.privateKey.export({type:'pkcs8',format:'pem'})});
    assert.equal(redirectResult.status,401);
    assert.equal(localAppleCalls,2); // Original origin only; the fixture rejects any redirect-target request.
    fixtureStatus = 200;
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
    // Real gateway + P-256 assertion + SQLite consumption. Only Apple Premium is doubled.
    const admissionChallenge = await (await call(ORIGIN, {operation:'challenge',kind:'assert',keyId:key.keyId})).json();
    const admissionAssertion = signedAssertion(key, assertionPayload('reply', key.keyId, admissionChallenge.challenge,
      TEST_BODY_HASH, TEST_TRANSACTION_HASH), 2);
    const admissionProof = {operation:'reply',keyId:key.keyId,challenge:admissionChallenge.challenge,
      assertion:admissionAssertion.toString('base64'),transactionJws:'fixture.purchase.proof'};
    const admissionHeaders = {'X-RepToday-Coach-Auth':JSON.stringify(admissionProof)};
    const admission = await call('https://runtime-fixture.invalid/admission', {}, admissionHeaders);
    assert.equal(admission.status,400);assert.deepEqual(await admission.json(),{error:'invalid_context'});
    const replay = await call('https://runtime-fixture.invalid/admission', {}, admissionHeaders);
    assert.equal(replay.status,401);assert.deepEqual(await replay.json(),{error:'unauthorized'});
    const operator = await call(ORIGIN, {}, {Authorization:'Bearer '+TEST_GATE});
    assert.equal(operator.status,401);assert.deepEqual(await operator.json(),{error:'unauthorized'});
    const finalRecord = await (await stub.fetch('https://fixture-record.invalid/')).json();
    assert.equal(finalRecord.counter,2);
    assert.deepEqual(Object.keys(finalRecord).sort(),['counter','expiresAt','publicKey','v']);
    const deniedChallenge = await (await call(ORIGIN, {operation:'challenge',kind:'assert',keyId:key.keyId})).json();
    const deniedJws = 'fixture.ineligible.purchase';
    const deniedAssertion = signedAssertion(key, assertionPayload('reply', key.keyId, deniedChallenge.challenge,
      TEST_BODY_HASH, hash(deniedJws)), 3);
    const deniedProof = {...admissionProof,challenge:deniedChallenge.challenge,
      assertion:deniedAssertion.toString('base64'),transactionJws:deniedJws};
    const forgedBytes = Buffer.from(deniedAssertion); forgedBytes[forgedBytes.length-1] ^= 1;
    const forgedAdmission = await call('https://runtime-fixture.invalid/admission', {}, {
      'X-RepToday-Coach-Auth':JSON.stringify({...deniedProof,assertion:forgedBytes.toString('base64')})});
    assert.equal(forgedAdmission.status,401);assert.deepEqual(await forgedAdmission.json(),{error:'unauthorized'});
    assert.equal((await (await stub.fetch('https://fixture-record.invalid/')).json()).counter,2);
    const deniedAdmission = await call('https://runtime-fixture.invalid/admission', {}, {
      'X-RepToday-Coach-Auth':JSON.stringify(deniedProof)});
    assert.equal(deniedAdmission.status,401);assert.deepEqual(await deniedAdmission.json(),{error:'unauthorized'});
    assert.equal((await (await stub.fetch('https://fixture-record.invalid/')).json()).counter,3);
    assert.equal(localAppleCalls,2);
    assert.equal(rejectedLocalCalls,0);
    assert.equal(localResponseCalls,0);
    console.log('validated: installed workerd native crypto, Apple verifier negatives, official API JWT/transport local double, proof-only gate ordering and SQLite atomic replay; zero external requests');
  }
} finally {await m.dispose();}
