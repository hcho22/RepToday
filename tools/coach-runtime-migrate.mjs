// Dedicated native Keychain child. Preparation tests inject every external boundary.
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createPrivateKey } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { Cloudflare, DeploymentFailure, TARGET, CUSTOM, RATE, HOLD,
  checkSettings, checkDomains, checkRoutes, ensureRule, verifyProtection, entrypoint,
  verifyClosedWorker, credentialsFromPacket, inspectionCredentialsFromPacket,
  readWranglerOAuth, stageWithWrangler, gateProbes } from './coach-production-deploy.mjs';

const requireThat = (condition, code) => { if (!condition) throw new DeploymentFailure(code); };
const identifier = value => typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);
const revisionValid = value => typeof value === 'string' && /^[a-f0-9]{40}$/.test(value);
const CLASS = 'CoachAuthenticationState', TAG = 'coach-security-v1';
const MODE = 'app-attest-storekit-v1';
const APPLE = Object.freeze({ appPrefix: 'APP_ATTEST_APP_PREFIX', appID: 'APP_STORE_APP_ID',
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
});

export function runtimePacket(packet, operation) {
  requireThat(['--stage', '--release', '--hold'].includes(operation), 'input');
  if (operation === '--hold') return inspectionCredentialsFromPacket(packet);
  if (operation === '--release') {
    requireThat(packet && Object.keys(packet).sort().join(',') === 'clientGate,wafToken', 'input');
    inspectionCredentialsFromPacket({ wafToken: packet.wafToken });
    requireThat(typeof packet.clientGate === 'string' && /^[a-f0-9]{64}$/.test(packet.clientGate), 'input');
    return packet;
  }
  requireThat(packet && Object.keys(packet).sort().join(',') ===
    'appID,appPrefix,clientGate,issuerID,keyID,openAI,privateKey,wafToken', 'input');
  credentialsFromPacket({ openAI: packet.openAI, clientGate: packet.clientGate, wafToken: packet.wafToken });
  requireThat(/^[A-Z0-9]{10}$/.test(packet.appPrefix ?? '') && /^[A-Z0-9]{10}$/.test(packet.keyID ?? '') &&
    typeof packet.appID === 'string' && /^[1-9][0-9]{0,15}$/.test(packet.appID) && Number.isSafeInteger(Number(packet.appID)) &&
    typeof packet.issuerID === 'string' && /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(packet.issuerID) &&
    typeof packet.privateKey === 'string' && packet.privateKey.length <= 4096 &&
    packet.privateKey.startsWith('-----BEGIN PRIVATE KEY-----\n'), 'input');
  try {
    const key = createPrivateKey(packet.privateKey);
    requireThat(key.asymmetricKeyType === 'ec' && key.asymmetricKeyDetails.namedCurve === 'prime256v1', 'input');
  } catch { throw new DeploymentFailure('input'); }
  return packet;
}

export class RuntimeCloudflare extends Cloudflare {
  async accountRequest(endpoint, method = 'GET', body) {
    const worker = `/accounts/${this.account}/workers/scripts/${TARGET.worker}`;
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

export function runtimeConfig(repository, revision, diagnostics = false) {
  requireThat(revisionValid(revision), 'revision');
  return { name: TARGET.worker, main: path.join(repository, 'proxy/src/coach-auth-worker.js'),
    compatibility_date: '2026-01-01', compatibility_flags: ['nodejs_compat'], workers_dev: false,
    preview_urls: false, routes: [], logpush: false, observability: { enabled: false }, send_metrics: false,
    vars: { COACH_AUTH_MODE: MODE, COACH_AUTH_SOURCE_REV: revision, ...(diagnostics ? { COACH_AUTH_GUARD_DIAGNOSTICS: '1' } : {}) },
    alias: { 'node-fetch': path.join(repository, 'proxy/src/apple-fetch.js') },
    durable_objects: { bindings: [{ name: 'COACH_AUTH_STATE', class_name: CLASS }] },
    migrations: [{ tag: TAG, new_sqlite_classes: [CLASS] }] };
}

export function checkRuntimeSettings(settings, revision, complete = false, diagnostics = false) {
  requireThat(settings && Array.isArray(settings.bindings), 'settings');
  const seen = new Set(); let state;
  for (const binding of settings.bindings) {
    requireThat(binding && typeof binding.name === 'string' && !seen.has(binding.name), 'settings'); seen.add(binding.name);
    if (binding.type === 'secret_text') requireThat(runtimeSecretNames.includes(binding.name), 'settings');
    else if (binding.name === 'COACH_AUTH_MODE') requireThat(binding.type === 'plain_text' && binding.text === MODE, 'settings');
    else if (binding.name === 'COACH_AUTH_GUARD_DIAGNOSTICS')
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
  if (revision) requireThat(seen.has('COACH_AUTH_GUARD_DIAGNOSTICS') === diagnostics, 'settings');
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

async function verifyRuntime(cf, worker, revision, complete, diagnostics = false) {
  const namespace = checkRuntimeSettings(await cf.accountRequest(worker + '/settings'), revision, complete, diagnostics);
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

export async function migrateRuntime({ cf, credentials, operation, revision, stageWorker, probe, report = () => {}, diagnostics = false }) {
  runtimePacket(credentials, operation);
  requireThat(operation === '--hold' || revisionValid(revision), 'revision');
  const worker = await confirm(cf); report(runtimeLines.confirmed);
  let previousNamespace;
  if (operation !== '--hold') {
    const settings = await cf.accountRequest(worker + '/settings');
    if (operation === '--stage' && !settings.bindings?.some(binding => binding.name === 'COACH_AUTH_STATE')) checkSettings(settings, true);
    else previousNamespace = await verifyRuntime(cf, worker, operation === '--release' ? revision : null, operation === '--release', diagnostics);
    checkSecrets(await cf.accountRequest(worker + '/secrets'), operation === '--release');
    await verifyClosedWorker(cf, worker);
  }
  await ensureRule(cf, CUSTOM, HOLD); await verifyProtection(cf, true);
  if (operation === '--hold') { report(runtimeLines.held); return; }
  report(runtimeLines.protected);
  if (operation === '--stage') {
    requireThat(typeof stageWorker === 'function', 'wrangler'); await stageWorker(cf.account);
    const namespace = await verifyRuntime(cf, worker, revision, false, diagnostics);
    requireThat(!previousNamespace || namespace === previousNamespace, 'namespace');
    const configured = await cf.accountRequest(worker + '/secrets'); checkSecrets(configured);
    for (const [source, name] of Object.entries(APPLE)) if (!configured.some(secret => secret.name === name)) {
      await cf.accountRequest(worker + '/secrets', 'PUT', { name, type: 'secret_text', text: credentials[source] });
    }
    checkSecrets(await cf.accountRequest(worker + '/secrets'), true);
    requireThat(await verifyRuntime(cf, worker, revision, true, diagnostics) === namespace, 'namespace');
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

export async function runtimeGateProbes(gate, fetchImpl = fetch) {
  await gateProbes(gate, fetchImpl);
  // A fixed forged proof cannot reach enrollment, Apple or the provider. No real prompt/proof.
  try {
    const response = await fetchImpl(TARGET.origin, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(5000),
      headers: { 'Content-Type': 'application/json', 'X-RepToday-Coach-Auth': '{}' }, body: '{}' });
    requireThat(response.status === 401 && response.redirected === false && response.body, 'gate');
    const reader = response.body.getReader(); let bytes = Buffer.alloc(0);
    try { while (true) { const part = await reader.read(); if (part.done) break;
      requireThat(bytes.length + part.value.length <= 256, 'gate'); bytes = Buffer.concat([bytes, part.value]); } }
    finally { await reader.cancel().catch(() => {}); }
    const result = JSON.parse(bytes.toString('utf8'));
    requireThat(Object.keys(result).join(',') === 'error' && result.error === 'unauthorized', 'gate');
  } catch { throw new DeploymentFailure('gate'); }
}

export function runtimeArguments(args) {
  requireThat(args.length >= 1 && args.length <= 2 && ['--stage', '--release', '--hold'].includes(args[0]), 'input');
  const diagnostics = args.length === 2;
  requireThat(!diagnostics || args[1] === '--auth-guard-diagnostics' && args[0] !== '--hold', 'input');
  return { operation: args[0], diagnostics };
}

async function main() {
  requireThat(!process.stdin.isTTY, 'input');
  const { operation, diagnostics } = runtimeArguments(process.argv.slice(2));
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
  const oauth = await readWranglerOAuth();
  await migrateRuntime({ cf: new RuntimeCloudflare(oauth, packet.wafToken), credentials: packet, operation, revision, diagnostics,
    stageWorker: account => stageWithWrangler(repository, account, oauth, root => runtimeConfig(root, revision, diagnostics)),
    probe: gate => runtimeGateProbes(gate), report: line => process.stdout.write(line + '\n') });
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { const code = error instanceof DeploymentFailure && runtimeFailures.includes(error.code) ? error.code : 'unexpected';
    process.stdout.write('blocked: ' + code + '\n'); process.exitCode = 78; });
}
