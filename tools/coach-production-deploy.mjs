// Invoked only by the dedicated native Keychain reader. No credential is printed or persisted.
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';

export const TARGET = Object.freeze({
  worker: 'reptoday-variety-language-proxy', zone: 'reptoday.app',
  hostname: 'coach.reptoday.app', origin: 'https://coach.reptoday.app/coach',
});
const CUSTOM = 'http_request_firewall_custom';
const RATE = 'http_ratelimit';
const host = `(http.host eq "${TARGET.hostname}")`;
const HOLD = Object.freeze({ ref: 'reptoday_coach_deployment_hold_v1',
  description: 'RepToday Coach deployment hold', action: 'block', expression: host, enabled: true });
const BOUNDARY = Object.freeze({ ref: 'reptoday_coach_path_boundary_v1',
  description: 'RepToday Coach exact public path', action: 'block',
  expression: `${host} and (http.request.uri.path ne "/coach")`, enabled: true });
const LIMIT = Object.freeze({ ref: 'reptoday_coach_ip_rate_v1',
  description: 'RepToday Coach 10 requests per 10 seconds per IP and location', action: 'block',
  // Captain-approved Free-plan scope: /coach is reserved across every hostname in this zone.
  expression: '(http.request.uri.path eq "/coach")',
  enabled: true, ratelimit: { characteristics: ['cf.colo.id', 'ip.src'], period: 10,
    requests_per_period: 10, mitigation_timeout: 10, requests_to_origin: false } });
const secretNames = ['CLIENT_SHARED_SECRET', 'OPENAI_API_KEY'];
const id = value => typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);
const requireThat = (condition, code) => { if (!condition) throw new DeploymentFailure(code); };

export class DeploymentFailure extends Error {
  constructor(code) { super('Deployment stopped'); this.code = code; }
}

export function credentialsFromPacket(packet) {
  requireThat(packet && Object.keys(packet).sort().join(',') === 'clientGate,openAI,wafToken', 'input');
  const safe = value => typeof value === 'string' && /^[A-Za-z0-9_-]{20,1024}$/.test(value);
  requireThat(safe(packet.openAI) && packet.openAI.startsWith('sk-') && safe(packet.wafToken) &&
    typeof packet.clientGate === 'string' && /^[0-9a-f]{64}$/.test(packet.clientGate), 'input');
  requireThat(new Set(Object.values(packet)).size === 3, 'input');
  return packet;
}

export class Cloudflare {
  constructor(oauth, waf, fetchImpl = fetch) {
    this.oauth = oauth; this.waf = waf; this.fetch = fetchImpl;
  }
  setScope(account, zone) {
    requireThat(id(account) && id(zone), 'scope');
    this.account = account; this.zone = zone;
  }
  async request(credential, endpoint, method = 'GET', body, allowMissing = false) {
    requireThat(endpoint.startsWith('/') && !endpoint.includes('..') && !endpoint.includes('#'), 'scope');
    const url = new URL(`https://api.cloudflare.com/client/v4${endpoint}`);
    requireThat(url.origin === 'https://api.cloudflare.com', 'scope');
    let response;
    try {
      response = await this.fetch(url, {
        method, redirect: 'error', signal: AbortSignal.timeout(20_000),
        headers: { Authorization: `Bearer ${credential}`, 'Content-Type': 'application/json' },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
      requireThat(!response.redirected && (!response.url || new URL(response.url).origin === url.origin), 'http');
      // CF bodies contain account identifiers. Never return them to stdout, logs or exceptions.
      const bytes = await boundedBody(response, 2 * 1024 * 1024);
      const data = JSON.parse(bytes);
      if (allowMissing && response.status === 404 && data.success === false &&
          data.errors?.some(error => [10003, 10007, 10090].includes(error.code))) return null;
      requireThat(response.ok && data.success === true && 'result' in data, credential === this.waf ? 'scope' : 'http');
      if (Array.isArray(data.result)) {
        requireThat(!data.result_info?.total_pages || data.result_info.total_pages <= 1, 'scope');
        requireThat(!data.result_info?.total_count || data.result_info.total_count === data.result.length, 'scope');
      }
      return data.result;
    } catch (error) {
      if (error instanceof DeploymentFailure) throw error;
      throw new DeploymentFailure('http');
    }
  }
  async accountRequest(endpoint, method = 'GET', body) {
    // The OAuth credential is the existing authenticated Wrangler credential, never the WAF token.
    const worker = `/accounts/${this.account}/workers/scripts/${TARGET.worker}`;
    const permitted = method === 'GET' && (endpoint === '/accounts' ||
      endpoint === `/zones?name=${TARGET.zone}&account.id=${this.account}&status=active` ||
      endpoint === `/accounts/${this.account}/workers/scripts` ||
      endpoint === `/accounts/${this.account}/workers/domains` ||
      endpoint === `/zones/${this.zone}/workers/routes` ||
      [worker + '/settings', worker + '/subdomain', worker + '/secrets'].includes(endpoint)) ||
      method === 'POST' && endpoint === worker + '/domains/changeset?replace_state=true' ||
      method === 'PUT' && endpoint === worker + '/domains/records' ||
      method === 'PUT' && endpoint === worker + '/secrets';
    requireThat(permitted, 'scope');
    if (method === 'PUT' && endpoint.endsWith('/secrets')) {
      requireThat(body?.type === 'secret_text' && secretNames.includes(body.name) &&
        Object.keys(body).sort().join(',') === 'name,text,type', 'secret');
    }
    if (method === 'PUT' && endpoint.endsWith('/domains/records')) {
      requireThat(body?.override_existing_origin === false && body.override_existing_dns_record === false &&
        body.override_scope === false && body.origins?.length === 1 &&
        body.origins[0].hostname === TARGET.hostname && body.origins[0].zone_id === this.zone, 'route');
    }
    return this.request(this.oauth, endpoint, method, body);
  }
  async zoneRequest(suffix, method = 'GET', body, allowMissing = false) {
    // This token can go only to this confirmed zone's Rulesets API. Never to Worker/secret/DNS APIs.
    requireThat(id(this.zone) && ['GET', 'POST', 'PATCH'].includes(method), 'scope');
    requireThat(/^\/rulesets(?:\/phases\/(?:http_request_firewall_custom|http_ratelimit)\/entrypoint|\/[a-f0-9]{32}(?:\/rules(?:\/[a-f0-9]{32})?)?)?$/.test(suffix), 'scope');
    return this.request(this.waf, `/zones/${this.zone}${suffix}`, method, body, allowMissing);
  }
}

async function boundedBody(response, maximum) {
  requireThat(response.body, 'http');
  const chunks = []; let count = 0;
  for await (const chunk of response.body) {
    count += chunk.length;
    if (count > maximum) { await response.body.cancel().catch(() => {}); throw new DeploymentFailure('http'); }
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}

function checkSettings(settings, requireSecrets = false) {
  requireThat(settings && Array.isArray(settings.bindings), 'settings');
  const seen = new Set();
  for (const binding of settings.bindings) {
    requireThat(!seen.has(binding.name), 'settings'); seen.add(binding.name);
    requireThat(binding.type === 'plain_text' && binding.name === 'ANTHROPIC_MODEL' && binding.text === 'claude-opus-4-8' ||
      binding.type === 'secret_text' && secretNames.includes(binding.name), 'settings');
  }
  requireThat(settings.observability?.enabled === false && settings.logpush !== true &&
    (!settings.tail_consumers || settings.tail_consumers.length === 0), 'settings');
  if (requireSecrets) requireThat(secretNames.every(name => seen.has(name)), 'secret');
}

function checkDomains(domains, account, zone, requireAttached = false) {
  requireThat(Array.isArray(domains), 'route');
  const assigned = domains.filter(domain => domain.service === TARGET.worker || domain.hostname === TARGET.hostname);
  requireThat(assigned.length <= 1 && assigned.every(domain => domain.hostname === TARGET.hostname &&
    domain.service === TARGET.worker && domain.zone_id === zone && domain.environment === 'production' &&
    (!domain.account_id || domain.account_id === account)), 'route');
  if (requireAttached) requireThat(assigned.length === 1, 'route');
  return assigned.length === 1;
}

function checkRoutes(routes) {
  requireThat(Array.isArray(routes) && routes.every(route => {
    if (route.script === TARGET.worker || typeof route.pattern !== 'string') return false;
    const hostname = route.pattern.replace(/^https?:\/\//, '').split('/')[0];
    const expression = hostname.split('*').map(part => part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*');
    return !new RegExp(`^${expression}$`, 'i').test(TARGET.hostname);
  }), 'route');
}

function ruleMatches(rule, expected, holdCanBeDisabled = false) {
  if (!rule || rule.ref !== expected.ref || rule.action !== expected.action || rule.expression !== expected.expression ||
      (!holdCanBeDisabled && rule.enabled !== expected.enabled)) return false;
  // Extra logging/skip/action parameters must never silently change the owned safety rule.
  if (rule.logging?.enabled || rule.action_parameters) return false;
  if (expected.ratelimit) {
    const actual = rule.ratelimit;
    return actual && Object.keys(expected.ratelimit).every(key => key === 'characteristics' ?
      Array.isArray(actual[key]) && [...actual[key]].sort().join(',') === [...expected.ratelimit[key]].sort().join(',') : actual[key] === expected.ratelimit[key]) &&
      !actual.counting_expression && !actual.score_per_period && !actual.score_response_header_name;
  }
  return !rule.ratelimit;
}

function checkRuleset(ruleset, phase) {
  if (ruleset === null) return;
  requireThat(ruleset && id(ruleset.id) && ruleset.kind === 'zone' && ruleset.phase === phase &&
    Array.isArray(ruleset.rules), 'rules');
  requireThat(ruleset.rules.every(rule => id(rule.id) && rule.action !== 'skip' && !rule.logging?.enabled), 'rules');
  const expected = phase === CUSTOM ? [HOLD, BOUNDARY] : [LIMIT];
  requireThat(expected.every(rule => ruleset.rules.filter(actual => actual.ref === rule.ref).length <= 1), 'rules');
  for (const rule of expected) {
    const actual = ruleset.rules.find(candidate => candidate.ref === rule.ref);
    if (actual) requireThat(ruleMatches(actual, rule, rule.ref === HOLD.ref), 'rules');
  }
  // Never consume an unrelated rule slot or purchase capacity, regardless of zone plan.
  if (phase === RATE) requireThat(ruleset.rules.every(rule => rule.ref === LIMIT.ref), 'rules');
}

async function entrypoint(cf, phase) {
  const ruleset = await cf.zoneRequest(`/rulesets/phases/${phase}/entrypoint`, 'GET', undefined, true);
  checkRuleset(ruleset, phase);
  return ruleset;
}

async function ensureRule(cf, phase, expected) {
  let ruleset = await entrypoint(cf, phase);
  if (ruleset === null) {
    await cf.zoneRequest('/rulesets', 'POST', {
      name: `RepToday ${phase} entrypoint`, kind: 'zone', phase, rules: [expected],
    });
  } else {
    const existing = ruleset.rules.find(rule => rule.ref === expected.ref);
    if (!existing) await cf.zoneRequest(`/rulesets/${ruleset.id}/rules`, 'POST', expected);
    else if (existing.enabled !== expected.enabled) {
      requireThat(expected.ref === HOLD.ref, 'rules');
      await cf.zoneRequest(`/rulesets/${ruleset.id}/rules/${existing.id}`, 'PATCH', { ...expected });
    }
  }
  ruleset = await entrypoint(cf, phase);
  requireThat(ruleMatches(ruleset?.rules.find(rule => rule.ref === expected.ref), expected), 'rules');
}

async function verifyProtection(cf, held) {
  const custom = await entrypoint(cf, CUSTOM);
  const rate = await entrypoint(cf, RATE);
  requireThat(ruleMatches(custom?.rules.find(rule => rule.ref === HOLD.ref), { ...HOLD, enabled: held }) &&
    ruleMatches(custom?.rules.find(rule => rule.ref === BOUNDARY.ref), BOUNDARY) &&
    ruleMatches(rate?.rules.find(rule => rule.ref === LIMIT.ref), LIMIT), 'rules');
}

export async function deploy({ cf, credentials, stageWorker, report = () => {}, probe }) {
  credentialsFromPacket(credentials);
  const accounts = await cf.accountRequest('/accounts');
  requireThat(Array.isArray(accounts) && accounts.length === 1 && id(accounts[0].id), 'account');
  cf.account = accounts[0].id;
  const zones = await cf.accountRequest(`/zones?name=${TARGET.zone}&account.id=${cf.account}&status=active`);
  requireThat(Array.isArray(zones) && zones.length === 1 && zones[0].name === TARGET.zone &&
    zones[0].status === 'active' && zones[0].account?.id === cf.account && id(zones[0].id), 'zone');
  // Captain explicitly approved a path-only rule on the existing Free zone. Refuse a
  // changed/unknown plan rather than purchasing capacity or guessing another configuration.
  requireThat(/^Free(?:\b|\s)/i.test(zones[0].plan?.name ?? ''), 'rate-plan');
  cf.setScope(cf.account, zones[0].id);
  const worker = `/accounts/${cf.account}/workers/scripts/${TARGET.worker}`;
  const scripts = await cf.accountRequest(`/accounts/${cf.account}/workers/scripts`);
  requireThat(Array.isArray(scripts) && scripts.filter(script => script.id === TARGET.worker).length <= 1, 'target');
  const exists = scripts.some(script => script.id === TARGET.worker);
  checkDomains(await cf.accountRequest(`/accounts/${cf.account}/workers/domains`), cf.account, cf.zone);
  checkRoutes(await cf.accountRequest(`/zones/${cf.zone}/workers/routes`));
  if (exists) checkSettings(await cf.accountRequest(worker + '/settings'));
  // Existing origins/routes are checked above. A changeset for a new Worker requires the
  // script to exist, so DNS conflicts are checked after staging, before provisioning keys.
  if (exists) await confirmDomainChangeset(cf, worker);
  await entrypoint(cf, CUSTOM); await entrypoint(cf, RATE);
  report('confirmed: approved account, zone and Worker target');

  // The hold is first and stays enabled on every failure until final verified release.
  await ensureRule(cf, CUSTOM, HOLD);
  await ensureRule(cf, CUSTOM, BOUNDARY);
  await ensureRule(cf, RATE, LIMIT);
  await verifyProtection(cf, true);
  report('protected: hostname held closed; path and rate rules verified');
  await stageWorker(cf.account);
  checkSettings(await cf.accountRequest(worker + '/settings'));
  await verifyClosedWorker(cf, worker);
  checkDomains(await cf.accountRequest(`/accounts/${cf.account}/workers/domains`), cf.account, cf.zone);
  checkRoutes(await cf.accountRequest(`/zones/${cf.zone}/workers/routes`));
  await confirmDomainChangeset(cf, worker);
  report('staged: Worker has no persistence, logs or development URLs');
  const configured = await cf.accountRequest(worker + '/secrets');
  requireThat(Array.isArray(configured) && configured.every(secret => secret.type === 'secret_text' &&
    secretNames.includes(secret.name)) && new Set(configured.map(secret => secret.name)).size === configured.length, 'secret');
  for (const name of secretNames) {
    // Never replace or rotate an existing server binding; provision only a missing binding
    // from its already-approved existing local item, solely on the approved Worker.
    if (!configured.some(secret => secret.name === name)) {
      await cf.accountRequest(worker + '/secrets', 'PUT', {
        name, type: 'secret_text', text: name === 'OPENAI_API_KEY' ? credentials.openAI : credentials.clientGate,
      });
    }
  }
  checkSettings(await cf.accountRequest(worker + '/settings'), true);
  await verifyClosedWorker(cf, worker);
  const attached = checkDomains(await cf.accountRequest(`/accounts/${cf.account}/workers/domains`), cf.account, cf.zone);
  if (!attached) {
    await confirmDomainChangeset(cf, worker);
    await cf.accountRequest(worker + '/domains/records', 'PUT', {
      override_scope: false, override_existing_origin: false, override_existing_dns_record: false,
      origins: [{ hostname: TARGET.hostname, zone_id: cf.zone }],
    });
  }
  checkDomains(await cf.accountRequest(`/accounts/${cf.account}/workers/domains`), cf.account, cf.zone, true);
  checkRoutes(await cf.accountRequest(`/zones/${cf.zone}/workers/routes`));
  checkSettings(await cf.accountRequest(worker + '/settings'), true);
  await verifyClosedWorker(cf, worker);
  await verifyProtection(cf, true);
  const custom = await entrypoint(cf, CUSTOM);
  const hold = custom.rules.find(rule => rule.ref === HOLD.ref);
  try {
    await cf.zoneRequest(`/rulesets/${custom.id}/rules/${hold.id}`, 'PATCH', { ...HOLD, enabled: false });
    await verifyProtection(cf, false);
    // Only no-model gate probes; authenticated malformed input cannot call the provider.
    requireThat(typeof probe === 'function', 'gate');
    await probe(credentials.clientGate);
  } catch (error) {
    // Best-effort re-close immediately if the release verification or paid-call-free gate probes fail.
    // If this fails too, the helper returns blocked and never retries or weakens protection.
    try { await ensureRule(cf, CUSTOM, HOLD); } catch { throw new DeploymentFailure('rules'); }
    throw error;
  }
  report(`deployed: ${TARGET.worker} ${TARGET.origin}; live model QA pending`);
}

async function verifyClosedWorker(cf, worker) {
  const state = await cf.accountRequest(worker + '/subdomain');
  requireThat(state?.enabled === false && state.previews_enabled === false, 'settings');
}

async function confirmDomainChangeset(cf, worker) {
  // The supported custom-domain changeset API is a preview, not an account/DNS mutation.
  const change = await cf.accountRequest(worker + '/domains/changeset?replace_state=true', 'POST',
    [{ hostname: TARGET.hostname, zone_id: cf.zone }]);
  requireThat(change && ['added', 'removed', 'updated', 'conflicting'].every(key => Array.isArray(change[key])), 'route');
  requireThat(change.conflicting.length === 0 && change.removed.length === 0 &&
    change.updated.every(domain => domain.hostname === TARGET.hostname && domain.modified === false) &&
    change.added.every(domain => domain.hostname === TARGET.hostname), 'route');
}

export async function gateProbes(gate, fetchImpl = fetch) {
  for (const authorization of [null, 'Bearer deliberately-invalid-coach-gate', `Bearer ${gate}`]) {
    let response;
    try {
      response = await fetchImpl(TARGET.origin, {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(15_000),
        headers: { 'Content-Type': 'application/json', ...(authorization ? { Authorization: authorization } : {}) },
        body: '{',
      });
      const expected = authorization === `Bearer ${gate}` ? 400 : 401;
      const body = JSON.parse(await boundedBody(response, 8192));
      requireThat(!response.redirected && response.status === expected &&
        (expected === 401 ? body.error === 'unauthorized' : typeof body.error === 'string'), 'gate');
    } catch { throw new DeploymentFailure('gate'); }
  }
}

export async function readWranglerOAuth(home = os.homedir(), environment = process.env) {
  // Refuse account/token/config overrides rather than silently choosing a different account.
  requireThat(!Object.keys(environment).some(key => /^(CLOUDFLARE_|CF_API_|CF_ACCOUNT_|WRANGLER_(API|ACCOUNT|CONFIG))/.test(key)), 'auth');
  let directory = path.join(home, '.wrangler');
  try { requireThat((await fs.stat(directory)).isDirectory(), 'auth'); }
  catch (error) {
    if (error instanceof DeploymentFailure) throw error;
    if (error.code !== 'ENOENT') throw new DeploymentFailure('auth');
    directory = path.join(home, 'Library/Preferences/.wrangler');
  }
  try {
    const text = await fs.readFile(path.join(directory, 'config/default.toml'), 'utf8');
    const token = /^oauth_token\s*=\s*"([^"\n]+)"\s*$/m.exec(text)?.[1];
    const expiry = /^expiration_time\s*=\s*"([^"\n]+)"\s*$/m.exec(text)?.[1];
    // Stop before mutation if Wrangler would need to refresh/write its shared auth file.
    requireThat(token && /^\S+$/.test(token) && Number.isFinite(Date.parse(expiry)) &&
      Date.parse(expiry) > Date.now() + 20 * 60_000, 'auth');
    return token;
  } catch { throw new DeploymentFailure('auth'); }
}

export function stagingConfig(repository) {
  return {
    name: TARGET.worker, main: path.join(repository, 'proxy/src/worker.js'), compatibility_date: '2026-01-01',
    workers_dev: false, preview_urls: false, routes: [], logpush: false,
    observability: { enabled: false }, send_metrics: false,
    vars: { ANTHROPIC_MODEL: 'claude-opus-4-8' },
  };
}

async function stageWithWrangler(repository, account, expectedOAuth) {
  // Refuse a changed or expiring shared credential before allowing Wrangler to select an account.
  requireThat(await readWranglerOAuth() === expectedOAuth, 'auth');
  const build = path.join(repository, 'build/coach-production-deploy');
  await fs.mkdir(build, { recursive: true, mode: 0o700 });
  const config = path.join(build, 'staging.json');
  // This file contains only public source/configuration. No account ID or credential enters it.
  await fs.writeFile(config, JSON.stringify(stagingConfig(repository)), { mode: 0o600 });
  const discard = path.join(build, 'wrangler-discard.log');
  try { await fs.unlink(discard); } catch (error) { if (error.code !== 'ENOENT') throw new DeploymentFailure('wrangler'); }
  await fs.symlink('/dev/null', discard);
  const env = { ...process.env, WRANGLER_LOG_PATH: discard, WRANGLER_SEND_METRICS: 'false',
    CI: 'true', NO_COLOR: '1' };
  delete env.NODE_OPTIONS; delete env.NODE_DEBUG; delete env.NODE_DEBUG_NATIVE;
  // Wrangler selects the sole existing authenticated account. The helper has verified it;
  // no account ID, token or Keychain credential is passed as an argument/environment variable.
  requireThat(id(account), 'account');
  const exit = await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [path.join(repository, 'proxy/node_modules/wrangler/bin/wrangler.js'),
      'deploy', '--config', config], { cwd: path.join(repository, 'proxy'), env, stdio: ['ignore', 'ignore', 'ignore'] });
    const timer = setTimeout(() => { child.kill('SIGTERM'); reject(new DeploymentFailure('wrangler')); }, 120_000);
    child.on('error', () => { clearTimeout(timer); reject(new DeploymentFailure('wrangler')); });
    child.on('close', code => { clearTimeout(timer); resolve(code); });
  });
  requireThat(exit === 0, 'wrangler');
}

async function main() {
  requireThat(process.argv.length === 3 && process.argv[2] === '--deploy' && !process.stdin.isTTY, 'input');
  const repository = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
  let bytes = Buffer.alloc(0);
  for await (const chunk of process.stdin) {
    requireThat(bytes.length + chunk.length <= 4096, 'input');
    const next = Buffer.concat([bytes, chunk]); bytes.fill(0); bytes = next;
  }
  let packet;
  try { packet = credentialsFromPacket(JSON.parse(bytes.toString('utf8'))); }
  catch { throw new DeploymentFailure('input'); }
  finally { bytes.fill(0); }
  const oauth = await readWranglerOAuth();
  const cf = new Cloudflare(oauth, packet.wafToken);
  await deploy({ cf, credentials: packet, stageWorker: account => stageWithWrangler(repository, account, oauth),
    report: line => process.stdout.write(`${line}\n`), probe: gateProbes });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => {
    const codes = new Set(['input', 'auth', 'account', 'zone', 'target', 'scope', 'rules', 'route',
      'settings', 'secret', 'wrangler', 'http', 'gate', 'rate-plan']);
    const code = error instanceof DeploymentFailure && codes.has(error.code) ? error.code : 'unexpected';
    process.stdout.write(`blocked: ${code}\n`);
    process.exitCode = 78;
  });
}
