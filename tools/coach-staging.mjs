// Separate, short-lived Coach staging Worker on workers.dev. It never addresses the production script,
// zone, rules or custom domain. Its rejections carry a fixed diagnostic label; it holds no model key.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { Cloudflare, DeploymentFailure, TARGET, readWranglerOAuth, stageWithWrangler } from './coach-production-deploy.mjs';
import { APPLE, CLASS, TAG, MODE, checkAppleCredentials, coachWorkerBuild, revisionValid } from './coach-runtime-migrate.mjs';

export const STAGING = 'reptoday-coach-staging';
export const STAGING_SECRET_NAMES = Object.freeze(['CLIENT_SHARED_SECRET', ...Object.values(APPLE)]);
export const stagingFailures = Object.freeze(['input', 'auth', 'account', 'subdomain', 'scope', 'http', 'wrangler',
  'revision', 'present', 'secret', 'settings', 'namespace', 'domain', 'probe', 'teardown', 'unexpected']);
export const stagingLines = Object.freeze({
  confirmed: 'confirmed: single account and workers.dev subdomain',
  deployed: origin => `deployed: ${STAGING} ${origin}; staging only, no model key`,
  verified: 'verified: staging bindings, own SQLite namespace, no custom domain, labelled no-model probes',
  inspected: origin => `inspect: present ${origin}; staging bindings, own SQLite namespace and no custom domain verified`,
  absent: `absent: ${STAGING}`,
  removed: `removed: ${STAGING}, its Durable Object namespace, custom domains and secrets; production identities unchanged`,
});
const requireThat = (condition, code) => { if (!condition) throw new DeploymentFailure(code); };
const identifier = value => typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);
const SUBDOMAIN = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;
// Must match the Worker's own staging-origin rule in proxy/src/coach-auth-worker.js.
const STAGING_ORIGIN = /^https:\/\/reptoday-coach-staging\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.workers\.dev\/coach$/;
const LABEL_HEADER = 'X-RepToday-Coach-Diagnostic';
requireThat(STAGING !== TARGET.worker, 'scope');

export const stagingOrigin = subdomain => {
  requireThat(typeof subdomain === 'string' && SUBDOMAIN.test(subdomain), 'subdomain');
  return `https://${STAGING}.${subdomain}.workers.dev/coach`;
};

export function stagingWorkerConfig(repository, revision, origin) {
  requireThat(revisionValid(revision), 'revision');
  requireThat(typeof origin === 'string' && STAGING_ORIGIN.test(origin), 'subdomain');
  return { name: STAGING, main: path.join(repository, 'proxy/src/coach-auth-worker.js'),
    ...coachWorkerBuild(repository), workers_dev: true,
    preview_urls: false, routes: [], logpush: false, observability: { enabled: false }, send_metrics: false,
    vars: { COACH_AUTH_MODE: MODE, COACH_AUTH_SOURCE_REV: revision, COACH_STAGING_ORIGIN: origin, COACH_STAGING_LABELS: '1' },
    durable_objects: { bindings: [{ name: 'COACH_AUTH_STATE', class_name: CLASS }] },
    migrations: [{ tag: TAG, new_sqlite_classes: [CLASS] }] };
}

export function stagingTeardownConfig(repository) {
  return { name: STAGING, main: path.join(repository, 'proxy/src/coach-staging-teardown-worker.js'),
    compatibility_date: '2026-01-01', workers_dev: false, preview_urls: false, routes: [], logpush: false,
    observability: { enabled: false }, send_metrics: false,
    migrations: [{ tag: 'coach-security-teardown-v1', deleted_classes: [CLASS] }] };
}

// Only exact staging mutations and account-level reads; production endpoints are unreachable by construction.
export class StagingCloudflare extends Cloudflare {
  async accountRequest(endpoint, method = 'GET', body) {
    const account = `/accounts/${this.account}`, script = `${account}/workers/scripts/${STAGING}`;
    const reads = ['/accounts', ...(identifier(this.account) ? [`${account}/workers/subdomain`, `${account}/workers/scripts`,
      `${account}/workers/durable_objects/namespaces`, `${account}/workers/domains`,
      `${script}/settings`, `${script}/secrets`, `${script}/subdomain`] : [])];
    const permitted = method === 'GET' && body === undefined && reads.includes(endpoint) ||
      identifier(this.account) && method === 'PUT' && endpoint === `${script}/secrets` && body?.type === 'secret_text' &&
        STAGING_SECRET_NAMES.includes(body.name) && Object.keys(body).sort().join(',') === 'name,text,type' &&
        typeof body.text === 'string' && body.text.length <= 4096 ||
      identifier(this.account) && method === 'DELETE' && body === undefined && endpoint === `${script}?force=true`;
    requireThat(permitted, 'scope');
    return this.request(this.oauth, endpoint, method, body);
  }

  async deleteStagingDomain(domain) {
    requireThat(identifier(this.account) && identifier(domain?.id) && domain.service === STAGING &&
      domain.hostname !== TARGET.hostname, 'scope');
    return this.request(this.oauth, `/accounts/${this.account}/workers/domains/${domain.id}`, 'DELETE');
  }
}

async function confirmAccount(cf) {
  const accounts = await cf.accountRequest('/accounts');
  requireThat(Array.isArray(accounts) && accounts.length === 1 && identifier(accounts[0]?.id), 'account');
  cf.account = accounts[0].id;
}
async function scriptPresent(cf) {
  const scripts = await cf.accountRequest(`/accounts/${cf.account}/workers/scripts`);
  requireThat(Array.isArray(scripts) && scripts.every(script => typeof script?.id === 'string'), 'http');
  return { staging: scripts.some(script => script.id === STAGING), production: scripts.some(script => script.id === TARGET.worker) };
}
async function confirmStaging(cf) {
  await confirmAccount(cf);
  const subdomain = await cf.accountRequest(`/accounts/${cf.account}/workers/subdomain`);
  return stagingOrigin(subdomain?.subdomain);
}
async function requireStagingAbsent(cf) {
  const scripts = await scriptPresent(cf);
  const namespaces = await cf.accountRequest(`/accounts/${cf.account}/workers/durable_objects/namespaces`);
  requireThat(Array.isArray(namespaces), 'namespace');
  const domains = await cf.accountRequest(`/accounts/${cf.account}/workers/domains`);
  requireThat(Array.isArray(domains), 'domain');
  requireThat(!scripts.staging && !namespaces.some(item => item.script === STAGING) &&
    !domains.some(item => item.service === STAGING), 'present');
}

async function stagingInventory(cf) {
  const scripts = await cf.accountRequest(`/accounts/${cf.account}/workers/scripts`);
  const namespaces = await cf.accountRequest(`/accounts/${cf.account}/workers/durable_objects/namespaces`);
  const domains = await cf.accountRequest(`/accounts/${cf.account}/workers/domains`);
  requireThat(Array.isArray(scripts) && scripts.every(item => typeof item?.id === 'string'), 'http');
  requireThat(Array.isArray(namespaces), 'namespace');
  requireThat(Array.isArray(domains), 'domain');
  return { scripts, namespaces, domains };
}

function teardownTargets(inventory) {
  const namespaces = inventory.namespaces.filter(item => item?.script === STAGING);
  const domains = inventory.domains.filter(item => item?.service === STAGING);
  const productionNamespaceIds = new Set(inventory.namespaces.filter(item => item?.script === TARGET.worker).map(item => item.id));
  const productionDomainIds = new Set(inventory.domains.filter(item => item?.service === TARGET.worker).map(item => item.id));
  requireThat(namespaces.length <= 1 && namespaces.every(item => identifier(item.id) && item.class === CLASS &&
    !productionNamespaceIds.has(item.id)), 'scope');
  requireThat(domains.every(item => identifier(item.id) && item.hostname !== TARGET.hostname &&
    !productionDomainIds.has(item.id)), 'scope');
  return { script: inventory.scripts.some(item => item.id === STAGING), namespaces, domains };
}

const productionIdentities = inventory => ({
  scripts: inventory.scripts.filter(item => item.id === TARGET.worker).map(item => item.id).sort(),
  namespaces: inventory.namespaces.filter(item => item.script === TARGET.worker).map(item => item.id).sort(),
  domains: inventory.domains.filter(item => item.service === TARGET.worker).map(item => item.id).sort(),
});

// Exact staging shape: its own vars, one SQLite namespace distinct from production, six secrets and
// no model key, no custom domain, workers.dev enabled, and no persistent logs or tail consumers.
export async function verifyStaging(cf, origin, revision = null) {
  const script = `/accounts/${cf.account}/workers/scripts/${STAGING}`;
  const settings = await cf.accountRequest(`${script}/settings`);
  requireThat(settings && Array.isArray(settings.bindings), 'settings');
  const seen = new Map();
  for (const binding of settings.bindings) {
    requireThat(binding && typeof binding.name === 'string' && !seen.has(binding.name), 'settings'); seen.set(binding.name, binding);
  }
  const vars = { COACH_AUTH_MODE: MODE, COACH_STAGING_ORIGIN: origin, COACH_STAGING_LABELS: '1' };
  requireThat([...seen.keys()].sort().join(',') === ['COACH_AUTH_SOURCE_REV', 'COACH_AUTH_STATE', ...Object.keys(vars),
    ...STAGING_SECRET_NAMES].sort().join(','), 'settings');
  for (const [name, text] of Object.entries(vars)) requireThat(seen.get(name).type === 'plain_text' && seen.get(name).text === text, 'settings');
  const source = seen.get('COACH_AUTH_SOURCE_REV');
  requireThat(source.type === 'plain_text' && revisionValid(source.text) && (!revision || source.text === revision), 'revision');
  for (const name of STAGING_SECRET_NAMES) requireThat(seen.get(name).type === 'secret_text', 'secret');
  const state = seen.get('COACH_AUTH_STATE');
  requireThat(state.type === 'durable_object_namespace' && state.class_name === CLASS && identifier(state.namespace_id) &&
    (!state.script_name || state.script_name === STAGING), 'namespace');
  requireThat((settings.observability === undefined || settings.observability?.enabled === false) &&
    (settings.logpush === undefined || settings.logpush === false) &&
    (settings.tail_consumers === undefined || Array.isArray(settings.tail_consumers) && !settings.tail_consumers.length), 'settings');
  const secrets = await cf.accountRequest(`${script}/secrets`);
  requireThat(Array.isArray(secrets) && secrets.map(secret => secret?.name).sort().join(',') === [...STAGING_SECRET_NAMES].sort().join(','), 'secret');
  const namespaces = await cf.accountRequest(`/accounts/${cf.account}/workers/durable_objects/namespaces`);
  requireThat(Array.isArray(namespaces), 'namespace');
  const own = namespaces.filter(item => item?.script === STAGING && item?.class === CLASS);
  const production = namespaces.filter(item => item?.script === TARGET.worker);
  requireThat(own.length === 1 && own[0].id === state.namespace_id && own[0].use_sqlite === true &&
    production.every(item => item.id !== state.namespace_id), 'namespace');
  const domains = await cf.accountRequest(`/accounts/${cf.account}/workers/domains`);
  requireThat(Array.isArray(domains) && !domains.some(domain => domain?.service === STAGING), 'domain');
  const subdomain = await cf.accountRequest(`${script}/subdomain`);
  requireThat(subdomain?.enabled === true && subdomain?.previews_enabled !== true, 'subdomain');
}

async function boundedText(response, maximum) {
  requireThat(response?.body, 'probe');
  const reader = response.body.getReader(); const chunks = []; let count = 0;
  try {
    while (true) {
      const part = await reader.read(); if (part.done) break;
      count += part.value.length; requireThat(count <= maximum, 'probe'); chunks.push(part.value);
    }
  } finally { await reader.cancel().catch(() => {}); }
  return Buffer.concat(chunks).toString('utf8');
}

// Two no-model probes. A fresh workers.dev script may need a moment before it answers, so either
// probe may wait (404, 5xx or no response) under one shared deadline and attempt budget for the whole phase, so
// worst-case time stays bounded; every answer must carry its exact label.
export async function stagingProbes(origin, fetchImpl = fetch, {
  now = () => performance.now(), wait = ms => new Promise(resolve => setTimeout(resolve, ms)),
} = {}) {
  const deadline = now() + 60_000;
  const probes = [[{}, 'worker_envelope/missing_proof'], [{ 'X-RepToday-Coach-Auth': '{}' }, 'worker_envelope/proof_envelope']];
  let attempts = 0;
  for (const [headers, label] of probes) {
    while (true) {
      attempts++;
      let status = null, text = null, observed = null, redirected = true;
      try {
        const response = await fetchImpl(origin, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10_000),
          headers: { 'Content-Type': 'application/json', ...headers }, body: '{}' });
        status = response.status; redirected = response.redirected !== false;
        observed = response.headers.get(LABEL_HEADER); text = await boundedText(response, 256);
      } catch {} // Classified below by what was observed; nothing from the failure is kept.
      if (status === 401 && !redirected && text === '{"error":"unauthorized"}' && observed === label) break;
      requireThat(attempts < 12 && (status === null || status === 404 || status >= 500) &&
        deadline - now() > 5_000, 'probe');
      await wait(5_000);
    }
  }
}

export async function deployStaging({ cf, credentials, revision, stageWorker, probe, report = () => {},
  gate = randomBytes(32).toString('hex') }) {
  requireThat(credentials && Object.keys(credentials).sort().join(',') === Object.keys(APPLE).sort().join(','), 'input');
  checkAppleCredentials(credentials);
  requireThat(revisionValid(revision), 'revision');
  requireThat(typeof gate === 'string' && /^[a-f0-9]{64}$/.test(gate), 'input');
  const origin = await confirmStaging(cf); report(stagingLines.confirmed);
  await requireStagingAbsent(cf);
  requireThat(typeof stageWorker === 'function', 'wrangler'); await stageWorker(cf.account, origin);
  const script = `/accounts/${cf.account}/workers/scripts/${STAGING}`;
  for (const [source, name] of Object.entries(APPLE))
    await cf.accountRequest(`${script}/secrets`, 'PUT', { name, type: 'secret_text', text: credentials[source] });
  // A fresh gate used only here: staging-issued challenges can never verify in production.
  await cf.accountRequest(`${script}/secrets`, 'PUT', { name: 'CLIENT_SHARED_SECRET', type: 'secret_text', text: gate });
  report(stagingLines.deployed(origin));
  await verifyStaging(cf, origin, revision);
  requireThat(typeof probe === 'function', 'probe'); await probe(origin);
  report(stagingLines.verified);
}

export async function inspectStaging({ cf, report = () => {} }) {
  const origin = await confirmStaging(cf);
  if (!(await scriptPresent(cf)).staging) { report(stagingLines.absent); return; }
  await verifyStaging(cf, origin); report(stagingLines.inspected(origin));
}

export async function teardownStaging({ cf, stageNamespaceDeletion, report = () => {} }) {
  await confirmAccount(cf);
  const before = await stagingInventory(cf);
  const targets = teardownTargets(before);
  if (!targets.script && !targets.namespaces.length && !targets.domains.length) { report(stagingLines.absent); return; }
  for (const domain of targets.domains) await cf.deleteStagingDomain(domain);
  if (targets.namespaces.length) {
    requireThat(typeof stageNamespaceDeletion === 'function', 'wrangler');
    await stageNamespaceDeletion(cf.account);
  }
  if (targets.script || targets.namespaces.length)
    await cf.accountRequest(`/accounts/${cf.account}/workers/scripts/${STAGING}?force=true`, 'DELETE');
  const after = await stagingInventory(cf);
  const remaining = teardownTargets(after);
  requireThat(!remaining.script && !remaining.namespaces.length && !remaining.domains.length &&
    JSON.stringify(productionIdentities(after)) === JSON.stringify(productionIdentities(before)), 'teardown');
  report(stagingLines.removed);
}

export const stagingFailureOutput = error =>
  'blocked: ' + (error instanceof DeploymentFailure && stagingFailures.includes(error.code) ? error.code : 'unexpected') + '\n';

async function main() {
  const operation = process.argv[2];
  requireThat(process.argv.length === 3 && ['--deploy', '--teardown', '--inspect'].includes(operation), 'input');
  const repository = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
  let credentials;
  if (operation === '--deploy') {
    requireThat(!process.stdin.isTTY, 'input');
    let bytes = Buffer.alloc(0);
    try {
      for await (const chunk of process.stdin) { requireThat(bytes.length + chunk.length <= 8192, 'input');
        const next = Buffer.concat([bytes, chunk]); bytes.fill(0); bytes = next; }
      credentials = JSON.parse(bytes.toString('utf8'));
    } catch { throw new DeploymentFailure('input'); } finally { bytes.fill(0); }
  }
  let revision;
  try { revision = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: repository, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); }
  catch { throw new DeploymentFailure('revision'); }
  const oauth = await readWranglerOAuth();
  const cf = new StagingCloudflare(oauth, undefined, fetch, { readOnly: operation === '--inspect' });
  const report = line => process.stdout.write(line + '\n');
  if (operation === '--deploy') await deployStaging({ cf, credentials, revision, report,
    stageWorker: (account, origin) => stageWithWrangler(repository, account, oauth, root => stagingWorkerConfig(root, revision, origin)),
    probe: origin => stagingProbes(origin) });
  else if (operation === '--teardown') await teardownStaging({ cf, report,
    stageNamespaceDeletion: account => stageWithWrangler(repository, account, oauth, stagingTeardownConfig) });
  else await inspectStaging({ cf, report });
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { process.stdout.write(stagingFailureOutput(error)); process.exitCode = 78; });
}
