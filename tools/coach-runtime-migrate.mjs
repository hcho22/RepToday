// Dedicated native Keychain child. Preparation tests inject every external boundary.
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createPrivateKey } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { Cloudflare, DeploymentFailure, TARGET, CUSTOM, RATE, HOLD,
  checkSettings, checkDomains, checkRoutes, ensureRule, verifyProtection, entrypoint,
  verifyClosedWorker, credentialsFromPacket, inspectionCredentialsFromPacket,
  readWranglerOAuth, stageWithWrangler, gateProbes, boundedGateProbe, gateFailureLine } from './coach-production-deploy.mjs';

const requireThat = (condition, code) => { if (!condition) throw new DeploymentFailure(code); };
const identifier = value => typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);
export const revisionValid = value => typeof value === 'string' && /^[a-f0-9]{40}$/.test(value);
const versionValid = value => typeof value === 'string' && /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(value);
const inspection = operation => ['--verify-candidate', '--verify-restored'].includes(operation);
export const CLASS = 'CoachAuthenticationState', TAG = 'coach-security-v1';
export const MODE = 'app-attest-storekit-v1';
export const APPLE = Object.freeze({ appPrefix: 'APP_ATTEST_APP_PREFIX', appID: 'APP_STORE_APP_ID',
  keyID: 'APP_STORE_KEY_ID', issuerID: 'APP_STORE_ISSUER_ID', privateKey: 'APP_STORE_PRIVATE_KEY' });
export const runtimeSecretNames = Object.freeze(['OPENAI_API_KEY', 'CLIENT_SHARED_SECRET', ...Object.values(APPLE)]);
export const runtimeFailures = Object.freeze(['input', 'auth', 'account', 'zone', 'target', 'scope',
  'rules', 'route', 'settings', 'secret', 'wrangler', 'http', 'gate', 'rate-plan', 'namespace', 'revision', 'rehold', 'unexpected']);
export const runtimeLines = Object.freeze({
  confirmed: 'confirmed: approved existing account, zone, Worker and attached origin',
  protected: 'protected: hostname held closed; existing boundary and rate protections verified',
  staged: 'staged: reviewed runtime source, SQLite namespace and server bindings verified; hostname held closed',
  released: `released: ${TARGET.worker} ${TARGET.origin}; genuine Apple and live model QA pending`,
  held: 'held: hostname closed; Worker, server bindings and security records preserved',
  verified: 'verified: exact active version and latest settings, namespace, secrets, privacy, protections and zero tails',
});

export function runtimePacket(packet, operation) {
  requireThat(['--stage', '--release', '--hold'].includes(operation) || inspection(operation), 'input');
  if (operation === '--hold' || inspection(operation)) return inspectionCredentialsFromPacket(packet);
  if (operation === '--release') {
    requireThat(packet && Object.keys(packet).sort().join(',') === 'clientGate,wafToken', 'input');
    inspectionCredentialsFromPacket({ wafToken: packet.wafToken });
    requireThat(typeof packet.clientGate === 'string' && /^[a-f0-9]{64}$/.test(packet.clientGate), 'input');
    return packet;
  }
  requireThat(packet && Object.keys(packet).sort().join(',') ===
    'appID,appPrefix,clientGate,issuerID,keyID,openAI,privateKey,wafToken', 'input');
  credentialsFromPacket({ openAI: packet.openAI, clientGate: packet.clientGate, wafToken: packet.wafToken });
  checkAppleCredentials(packet);
  return packet;
}

// The five App Attest/App Store items, shared by the runtime stage and the separate staging deploy.
export function checkAppleCredentials(packet) {
  requireThat(packet && /^[A-Z0-9]{10}$/.test(packet.appPrefix ?? '') && /^[A-Z0-9]{10}$/.test(packet.keyID ?? '') &&
    typeof packet.appID === 'string' && /^[1-9][0-9]{0,15}$/.test(packet.appID) && Number.isSafeInteger(Number(packet.appID)) &&
    typeof packet.issuerID === 'string' && /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(packet.issuerID) &&
    typeof packet.privateKey === 'string' && packet.privateKey.length <= 4096 &&
    packet.privateKey.startsWith('-----BEGIN PRIVATE KEY-----\n'), 'input');
  try {
    const key = createPrivateKey(packet.privateKey);
    requireThat(key.asymmetricKeyType === 'ec' && key.asymmetricKeyDetails.namedCurve === 'prime256v1', 'input');
  } catch { throw new DeploymentFailure('input'); }
}

export class RuntimeCloudflare extends Cloudflare {
  async accountRequest(endpoint, method = 'GET', body) {
    const worker = `/accounts/${this.account}/workers/scripts/${TARGET.worker}`;
    if (method === 'GET' && body === undefined && identifier(this.account) &&
        ([worker + '/deployments', worker + '/tails'].includes(endpoint) ||
         endpoint.startsWith(worker + '/versions/') && versionValid(endpoint.slice((worker + '/versions/').length))))
      return this.request(this.oauth, endpoint);
    if (method === 'GET' && identifier(this.account) &&
        endpoint === `/accounts/${this.account}/workers/durable_objects/namespaces`) {
      return this.request(this.oauth, endpoint);
    }
    if (method === 'PUT' && endpoint === worker + '/secrets') {
      requireThat(identifier(this.account) && body?.type === 'secret_text' && runtimeSecretNames.includes(body.name) &&
        Object.keys(body).sort().join(',') === 'name,text,type' && typeof body.text === 'string' && body.text.length <= 4096, 'secret');
      return this.request(this.oauth, endpoint, method, body);
    }
    // The migration never attaches a hostname, edits DNS or creates another Worker.
    requireThat(method === 'GET' && body === undefined, 'scope');
    return super.accountRequest(endpoint, method, body);
  }
}

// Build settings shared by every Wrangler bundle of the Coach Worker: production, staging and the
// workerd test bundles in proxy/test/workerd-auth.mjs, so the tests run the module graph that ships.
// node:crypto resolves to workerd's native module (proxy/src/native-crypto.cjs explains why).
export function coachWorkerBuild(repository) {
  const nativeCrypto = path.join(repository, 'proxy/src/native-crypto.cjs');
  return { compatibility_date: '2026-01-01', compatibility_flags: ['nodejs_compat'],
    alias: { 'node-fetch': path.join(repository, 'proxy/src/apple-fetch.js'), crypto: nativeCrypto, 'node:crypto': nativeCrypto } };
}

export function runtimeConfig(repository, revision, diagnostics = false, finalDiagnostics = false) {
  requireThat(revisionValid(revision), 'revision');
  requireThat(typeof diagnostics === 'boolean' && typeof finalDiagnostics === 'boolean', 'input');
  return { name: TARGET.worker, main: path.join(repository, 'proxy/src/coach-auth-worker.js'),
    ...coachWorkerBuild(repository), workers_dev: false,
    preview_urls: false, routes: [], logpush: false, observability: { enabled: false }, send_metrics: false,
    vars: { COACH_AUTH_MODE: MODE, COACH_AUTH_SOURCE_REV: revision, ...(diagnostics ? { COACH_AUTH_GUARD_DIAGNOSTICS: '1' } : {}),
      ...(finalDiagnostics ? { COACH_FINAL_AUTH_DIAGNOSTICS: '1' } : {}) },
    durable_objects: { bindings: [{ name: 'COACH_AUTH_STATE', class_name: CLASS }] },
    migrations: [{ tag: TAG, new_sqlite_classes: [CLASS] }] };
}

export function checkRuntimeSettings(settings, revision, complete = false, diagnostics = false, finalDiagnostics = false) {
  requireThat(typeof diagnostics === 'boolean' && typeof finalDiagnostics === 'boolean' &&
    settings && Array.isArray(settings.bindings), 'settings');
  const seen = new Set(); let state;
  for (const binding of settings.bindings) {
    requireThat(binding && typeof binding.name === 'string' && !seen.has(binding.name), 'settings'); seen.add(binding.name);
    if (binding.type === 'secret_text') requireThat(runtimeSecretNames.includes(binding.name), 'settings');
    else if (binding.name === 'COACH_AUTH_MODE') requireThat(binding.type === 'plain_text' && binding.text === MODE, 'settings');
    else if (['COACH_AUTH_GUARD_DIAGNOSTICS', 'COACH_FINAL_AUTH_DIAGNOSTICS'].includes(binding.name))
      requireThat(binding.type === 'plain_text' && binding.text === '1', 'settings');
    else if (binding.name === 'COACH_AUTH_SOURCE_REV') requireThat(binding.type === 'plain_text' &&
      revisionValid(binding.text) && (!revision || binding.text === revision), 'revision');
    else if (binding.name === 'COACH_AUTH_STATE') {
      requireThat(binding.type === 'durable_object_namespace' && binding.class_name === CLASS &&
        identifier(binding.namespace_id) && (!binding.script_name || binding.script_name === TARGET.worker) &&
        (!binding.environment || binding.environment === 'production'), 'namespace'); state = binding;
    } else throw new DeploymentFailure('settings');
  }
  requireThat(state && seen.has('COACH_AUTH_MODE') && seen.has('COACH_AUTH_SOURCE_REV'), 'settings');
  // Pre-stage inspection permits either approved state; a pinned release must match the explicit option.
  if (revision) requireThat(seen.has('COACH_AUTH_GUARD_DIAGNOSTICS') === diagnostics &&
    seen.has('COACH_FINAL_AUTH_DIAGNOSTICS') === finalDiagnostics, 'settings');
  requireThat((settings.observability === undefined || settings.observability?.enabled === false) &&
    (settings.logpush === undefined || settings.logpush === false) &&
    (settings.tail_consumers === undefined || Array.isArray(settings.tail_consumers) && !settings.tail_consumers.length), 'settings');
  if (settings.observability) for (const section of ['logs', 'traces']) {
    const value = settings.observability[section];
    requireThat(value === undefined || value && value.enabled === false && value.persist !== true &&
      value.invocation_logs !== true && (!value.destinations || Array.isArray(value.destinations) && !value.destinations.length), 'settings');
  }
  if (complete) requireThat(runtimeSecretNames.every(name => seen.has(name)), 'secret');
  return state.namespace_id;
}

function checkSecrets(secrets, complete = false) {
  requireThat(Array.isArray(secrets) && secrets.every(secret => secret?.type === 'secret_text' && runtimeSecretNames.includes(secret.name)) &&
    new Set(secrets.map(secret => secret.name)).size === secrets.length, 'secret');
  requireThat(['OPENAI_API_KEY', 'CLIENT_SHARED_SECRET'].every(name => secrets.some(secret => secret.name === name)), 'secret');
  if (complete) requireThat(runtimeSecretNames.every(name => secrets.some(secret => secret.name === name)), 'secret');
}

async function confirm(cf) {
  const accounts = await cf.accountRequest('/accounts');
  requireThat(Array.isArray(accounts) && accounts.length === 1 && identifier(accounts[0].id), 'account'); cf.account = accounts[0].id;
  const zones = await cf.accountRequest(`/zones?name=${TARGET.zone}&account.id=${cf.account}&status=active`);
  requireThat(Array.isArray(zones) && zones.length === 1 && zones[0].name === TARGET.zone && zones[0].status === 'active' &&
    zones[0].account?.id === cf.account && identifier(zones[0].id), 'zone');
  requireThat(/^Free(?:\b|\s)/i.test(zones[0].plan?.name ?? ''), 'rate-plan'); cf.setScope(cf.account, zones[0].id);
  const scripts = await cf.accountRequest(`/accounts/${cf.account}/workers/scripts`);
  requireThat(Array.isArray(scripts) && scripts.filter(script => script.id === TARGET.worker).length === 1, 'target');
  checkDomains(await cf.accountRequest(`/accounts/${cf.account}/workers/domains`), cf.account, cf.zone, true);
  checkRoutes(await cf.accountRequest(`/zones/${cf.zone}/workers/routes`));
  // Existing protections must already be present. Do not create capacity or fill missing rules.
  const custom = await entrypoint(cf, CUSTOM);
  const hold = custom?.rules.find(rule => rule.ref === HOLD.ref);
  requireThat(hold && typeof hold.enabled === 'boolean', 'rules'); await verifyProtection(cf, hold.enabled);
  return `/accounts/${cf.account}/workers/scripts/${TARGET.worker}`;
}

async function verifyRuntime(cf, worker, revision, complete, diagnostics = false, finalDiagnostics = false) {
  const namespace = checkRuntimeSettings(await cf.accountRequest(worker + '/settings'), revision, complete, diagnostics, finalDiagnostics);
  await verifyClosedWorker(cf, worker);
  const scripts = await cf.accountRequest(`/accounts/${cf.account}/workers/scripts`);
  requireThat(Array.isArray(scripts) && scripts.filter(script => script.id === TARGET.worker && script.migration_tag === TAG).length === 1, 'namespace');
  // Cloudflare's official namespace API exposes class/script/use_sqlite. Missing fields stop.
  const namespaces = await cf.accountRequest(`/accounts/${cf.account}/workers/durable_objects/namespaces`);
  requireThat(Array.isArray(namespaces) && namespaces.filter(item => item.id === namespace).length === 1, 'namespace');
  const owned = namespaces.find(item => item.id === namespace);
  requireThat(owned.class === CLASS && owned.script === TARGET.worker && owned.use_sqlite === true &&
    namespaces.filter(item => item.script === TARGET.worker && item.class === CLASS).length === 1, 'namespace');
  checkDomains(await cf.accountRequest(`/accounts/${cf.account}/workers/domains`), cf.account, cf.zone, true);
  checkRoutes(await cf.accountRequest(`/zones/${cf.zone}/workers/routes`));
  return namespace;
}

export async function migrateRuntime({ cf, credentials, operation, revision, stageWorker, probe, report = () => {}, diagnostics = false, finalDiagnostics = false }) {
  requireThat(['--stage', '--release', '--hold'].includes(operation), 'input');
  runtimePacket(credentials, operation);
  requireThat(typeof diagnostics === 'boolean' && typeof finalDiagnostics === 'boolean' &&
    (operation !== '--hold' || !diagnostics && !finalDiagnostics), 'input');
  requireThat(operation === '--hold' || revisionValid(revision), 'revision');
  const worker = await confirm(cf); report(runtimeLines.confirmed);
  let previousNamespace;
  if (operation !== '--hold') {
    const settings = await cf.accountRequest(worker + '/settings');
    if (operation === '--stage' && !settings.bindings?.some(binding => binding.name === 'COACH_AUTH_STATE')) checkSettings(settings, true);
    else previousNamespace = await verifyRuntime(cf, worker, operation === '--release' ? revision : null, operation === '--release', diagnostics, finalDiagnostics);
    checkSecrets(await cf.accountRequest(worker + '/secrets'), operation === '--release');
    await verifyClosedWorker(cf, worker);
  }
  await ensureRule(cf, CUSTOM, HOLD); await verifyProtection(cf, true);
  if (operation === '--hold') { report(runtimeLines.held); return; }
  report(runtimeLines.protected);
  if (operation === '--stage') {
    requireThat(typeof stageWorker === 'function', 'wrangler'); await stageWorker(cf.account);
    const namespace = await verifyRuntime(cf, worker, revision, false, diagnostics, finalDiagnostics);
    requireThat(!previousNamespace || namespace === previousNamespace, 'namespace');
    const configured = await cf.accountRequest(worker + '/secrets'); checkSecrets(configured);
    for (const [source, name] of Object.entries(APPLE)) if (!configured.some(secret => secret.name === name)) {
      await cf.accountRequest(worker + '/secrets', 'PUT', { name, type: 'secret_text', text: credentials[source] });
    }
    checkSecrets(await cf.accountRequest(worker + '/secrets'), true);
    requireThat(await verifyRuntime(cf, worker, revision, true, diagnostics, finalDiagnostics) === namespace, 'namespace');
    await verifyProtection(cf, true); report(runtimeLines.staged); return;
  }
  const custom = await entrypoint(cf, CUSTOM), hold = custom.rules.find(rule => rule.ref === HOLD.ref);
  try {
    requireThat(typeof probe === 'function', 'gate');
    await cf.zoneRequest(`/rulesets/${custom.id}/rules/${hold.id}`, 'PATCH', { ...HOLD, enabled: false });
    await verifyProtection(cf, false); await probe(credentials.clientGate);
  } catch (error) {
    try { await ensureRule(cf, CUSTOM, HOLD); await verifyProtection(cf, true); }
    catch { throw new DeploymentFailure('rehold'); }
    throw error;
  }
  report(runtimeLines.released);
}

// Private operation manifests contain metadata, never credentials. They pin the current
// reviewed owner separately from the source/version being inspected (which may be older).
export function checkRuntimeExpectation(value, ownerRevision, candidate = false) {
  requireThat(value && Object.keys(value).sort().join(',') ===
    'accountId,held,namespaceId,ownerRevision,sourceRevision,versionId,worker,zoneId', 'input');
  requireThat(revisionValid(ownerRevision) && value.ownerRevision === ownerRevision &&
    revisionValid(value.sourceRevision) && (!candidate || value.sourceRevision === ownerRevision), 'revision');
  requireThat(value.worker === TARGET.worker && identifier(value.accountId) && identifier(value.zoneId) &&
    identifier(value.namespaceId) && versionValid(value.versionId) && typeof value.held === 'boolean', 'target');
  return value;
}

function checkRuntimeCompatibility(runtime) {
  requireThat(runtime?.compatibility_date === '2026-01-01' &&
    JSON.stringify(runtime.compatibility_flags) === '["nodejs_compat"]', 'settings');
}

export function checkRuntimeVersion(version, expected, finalDiagnostics = false) {
  requireThat(version?.id === expected.versionId, 'revision');
  checkRuntimeCompatibility(version.resources?.script_runtime);
  requireThat(checkRuntimeSettings({ bindings: version.resources?.bindings }, expected.sourceRevision,
    true, false, finalDiagnostics) === expected.namespaceId, 'namespace');
  // Active version metadata and latest Worker settings are separate surfaces.
  requireThat(['off', undefined].includes(version.resources?.script?.placement_mode), 'settings');
}

export async function verifyRuntimeExpectation({ cf, expected, ownerRevision, candidate = false, report = () => {} }) {
  checkRuntimeExpectation(expected, ownerRevision, candidate);
  const worker = await confirm(cf);
  requireThat(cf.account === expected.accountId && cf.zone === expected.zoneId, 'target');
  report(runtimeLines.confirmed);
  requireThat(await verifyRuntime(cf, worker, expected.sourceRevision, true, false, candidate) === expected.namespaceId, 'namespace');
  const settings = await cf.accountRequest(worker + '/settings');
  checkRuntimeCompatibility(settings);
  requireThat(settings.usage_model === 'standard' && JSON.stringify(settings.placement ?? {}) === '{}' &&
    Array.isArray(settings.tags ?? []) && !(settings.tags ?? []).length && settings.logpush === false, 'settings');
  checkSecrets(await cf.accountRequest(worker + '/secrets'), true);
  const active = await cf.accountRequest(worker + '/deployments');
  const deployment = active?.deployments?.[0];
  requireThat(Array.isArray(deployment?.versions) && deployment.versions.length === 1 &&
    deployment.versions[0].percentage === 100 && deployment.versions[0].version_id === expected.versionId, 'revision');
  checkRuntimeVersion(await cf.accountRequest(worker + '/versions/' + expected.versionId), expected, candidate);
  await verifyProtection(cf, expected.held);
  const tails = await cf.accountRequest(worker + '/tails');
  requireThat(Array.isArray(tails) && tails.length === 0, 'settings');
  // Detect traffic movement during inspection. No retry or optimistic success on drift.
  const final = await cf.accountRequest(worker + '/deployments');
  requireThat(JSON.stringify(final?.deployments?.[0]) === JSON.stringify(deployment), 'revision');
  report(runtimeLines.verified);
}

// Two synthetic, no-model coverage requests. Enrollment CBOR is rejected before
// storage or Apple verification. The returned token is kept only in this stack.
// Call only during a separately authorized capture after its attached marker.
export async function runtimeCoverageProbes(fetchImpl = fetch) {
  const keyId = Buffer.alloc(32).toString('base64');
  async function post(body, status) {
    try {
      const response = await fetchImpl(TARGET.origin, { method: 'POST', redirect: 'error',
        signal: AbortSignal.timeout(5000), headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      requireThat(response.status === status && response.redirected === false && response.body, 'gate');
      let bytes = Buffer.alloc(0);
      const reader = response.body.getReader();
      try { while (true) { const part = await reader.read(); if (part.done) break;
        requireThat(bytes.length + part.value.length <= 1024, 'gate'); bytes = Buffer.concat([bytes, part.value]); } }
      finally { await reader.cancel().catch(() => {}); }
      return JSON.parse(bytes.toString('utf8'));
    } catch { throw new DeploymentFailure('gate'); }
  }
  const challenge = await post({ operation: 'challenge', kind: 'enroll', keyId }, 200);
  requireThat(Object.keys(challenge).join(',') === 'challenge' && typeof challenge.challenge === 'string' &&
    challenge.challenge.length <= 512, 'gate');
  const denied = await post({ operation: 'enroll', keyId, challenge: challenge.challenge, attestation: 'AA==' }, 401);
  requireThat(Object.keys(denied).join(',') === 'error' && denied.error === 'unauthorized', 'gate');
}

export async function runtimeGateProbes(gate, fetchImpl = fetch, {
  now = () => performance.now(), wait = ms => new Promise(resolve => setTimeout(resolve, ms)),
} = {}) {
  // One readiness deadline covers every release probe; each may absorb the same bounded hold-like edge denial.
  const readinessDeadline = now() + 45_000;
  await gateProbes(gate, fetchImpl, { now, wait, readinessDeadline, retryEveryStage: true });
  // A fixed forged proof cannot reach enrollment, Apple or the provider. No real prompt/proof.
  await boundedGateProbe(fetchImpl, { stage: 'forged-proof', headers: { 'X-RepToday-Coach-Auth': '{}' }, body: '{}', expected: 401,
    accept: (parsed, response) => response.redirected === false && parsed !== null && typeof parsed === 'object' &&
      Object.keys(parsed).join(',') === 'error' && parsed.error === 'unauthorized',
    bodyLimit: 256, requestTimeout: 5_000, readiness: true, retry: true, readinessDeadline, now, wait });
}

export function runtimeArguments(args) {
  requireThat(args.length >= 1 && args.length <= 3 && (['--stage', '--release', '--hold'].includes(args[0]) || inspection(args[0])), 'input');
  const options = args.slice(1);
  requireThat(new Set(options).size === options.length && options.every(option =>
    ['--auth-guard-diagnostics', '--final-auth-diagnostics'].includes(option)) &&
    (['--stage', '--release'].includes(args[0]) || !options.length), 'input');
  return { operation: args[0], diagnostics: options.includes('--auth-guard-diagnostics'),
    finalDiagnostics: options.includes('--final-auth-diagnostics') };
}

async function main() {
  if (process.argv.length === 3 && process.argv[2] === '--coverage-probes') {
    await runtimeCoverageProbes();
    process.stdout.write('coverage: synthetic Worker and malformed-enrollment probes completed; tail coverage still required\n');
    return;
  }
  requireThat(!process.stdin.isTTY, 'input');
  const { operation, diagnostics, finalDiagnostics } = runtimeArguments(process.argv.slice(2));
  const repository = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
  let bytes = Buffer.alloc(0), packet;
  try {
    for await (const chunk of process.stdin) { requireThat(bytes.length + chunk.length <= 12_288, 'input');
      const next = Buffer.concat([bytes, chunk]); bytes.fill(0); bytes = next; }
    packet = runtimePacket(JSON.parse(bytes.toString('utf8')), operation);
  } catch { throw new DeploymentFailure('input'); } finally { bytes.fill(0); }
  let revision;
  try { revision = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: repository, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); }
  catch { throw new DeploymentFailure('revision'); }
  // Parse the bounded manifest before Wrangler OAuth access. Never print its identifiers.
  let expected;
  if (inspection(operation)) {
    try {
      const file = path.join(repository, 'build/coach-runtime-migration',
        operation === '--verify-candidate' ? 'candidate.json' : 'baseline.json');
      const info = await fs.lstat(file);
      requireThat(info.isFile() && !info.isSymbolicLink() && info.size <= 2048, 'input');
      const contents = await fs.readFile(file);
      requireThat(contents.length <= 2048, 'input');
      expected = checkRuntimeExpectation(JSON.parse(contents.toString('utf8')), revision, operation === '--verify-candidate');
    } catch (error) { if (error instanceof DeploymentFailure) throw error; throw new DeploymentFailure('input'); }
  }
  const oauth = await readWranglerOAuth();
  if (inspection(operation)) return verifyRuntimeExpectation({
    cf: new RuntimeCloudflare(oauth, packet.wafToken), expected, ownerRevision: revision,
    candidate: operation === '--verify-candidate', report: line => process.stdout.write(line + '\n') });
  await migrateRuntime({ cf: new RuntimeCloudflare(oauth, packet.wafToken), credentials: packet, operation, revision, diagnostics, finalDiagnostics,
    stageWorker: account => stageWithWrangler(repository, account, oauth, root => runtimeConfig(root, revision, diagnostics, finalDiagnostics)),
    probe: gate => runtimeGateProbes(gate), report: line => process.stdout.write(line + '\n') });
}
// The only failure output: an optional fixed-vocabulary probe line, then the closed stop code.
export function runtimeFailureOutput(error) {
  const code = error instanceof DeploymentFailure && runtimeFailures.includes(error.code) ? error.code : 'unexpected';
  const probe = code === 'gate' ? gateFailureLine(error) : null;
  return (probe ? probe + '\n' : '') + 'blocked: ' + code + '\n';
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { process.stdout.write(runtimeFailureOutput(error)); process.exitCode = 78; });
}
