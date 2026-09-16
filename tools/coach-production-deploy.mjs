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

export function gateFailureLine(error) {
  const diagnostic = error instanceof DeploymentFailure && error.code === 'gate' ? error.gateDiagnostic : null;
  if (!diagnostic || Object.keys(diagnostic).sort().join(',') !== 'contract,failure,redirected,stage,status' ||
      !['missing-authorization', 'wrong-authorization', 'correct-authorization'].includes(diagnostic.stage) ||
      !['request', 'timeout', 'body', 'size', 'json', 'redirect', 'status', 'contract'].includes(diagnostic.failure) ||
      !(diagnostic.status === null || Number.isInteger(diagnostic.status) && diagnostic.status >= 100 && diagnostic.status <= 599) ||
      !['unknown', 'yes', 'no'].includes(diagnostic.redirected) ||
      !['not-read', 'body-unavailable', 'oversized', 'non-json', 'unauthorized', 'string-error', 'invalid-error'].includes(diagnostic.contract)) return null;
  return `gate: probe ${diagnostic.stage} failure ${diagnostic.failure} status ${diagnostic.status ?? 'none'} ` +
    `redirected ${diagnostic.redirected} contract ${diagnostic.contract}`;
}

export function credentialsFromPacket(packet) {
  requireThat(packet && Object.keys(packet).sort().join(',') === 'clientGate,openAI,wafToken', 'input');
  const safe = value => typeof value === 'string' && /^[A-Za-z0-9_-]{20,1024}$/.test(value);
  requireThat(safe(packet.openAI) && packet.openAI.startsWith('sk-') && safe(packet.wafToken) &&
    typeof packet.clientGate === 'string' && /^[0-9a-f]{64}$/.test(packet.clientGate), 'input');
  requireThat(new Set(Object.values(packet)).size === 3, 'input');
  return packet;
}

export function inspectionCredentialsFromPacket(packet) {
  requireThat(packet && Object.keys(packet).join(',') === 'wafToken' &&
    typeof packet.wafToken === 'string' && /^[A-Za-z0-9_-]{20,1024}$/.test(packet.wafToken), 'input');
  return packet;
}

export class Cloudflare {
  constructor(oauth, waf, fetchImpl = fetch, { readOnly = false } = {}) {
    this.oauth = oauth; this.waf = waf; this.fetch = fetchImpl;
    Object.defineProperty(this, 'readOnly', { value: readOnly });
  }
  setScope(account, zone) {
    requireThat(id(account) && id(zone), 'scope');
    this.account = account; this.zone = zone;
  }
  async request(credential, endpoint, method = 'GET', body, allowMissing = false) {
    requireThat(!this.readOnly || method === 'GET' && body === undefined, 'scope');
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

async function boundedBody(response, maximum, onTooLarge = () => {}) {
  requireThat(response.body, 'http');
  const chunks = []; let count = 0;
  for await (const chunk of response.body) {
    count += chunk.length;
    if (count > maximum) { onTooLarge(); await response.body.cancel().catch(() => {}); throw new DeploymentFailure('http'); }
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
  // Cloudflare omits observability on settings GET after Wrangler explicitly disables it.
  // Accept only that observed omission or literal false; null/malformed/enabled still stop.
  requireThat((settings.observability === undefined || settings.observability?.enabled === false) && settings.logpush !== true &&
    (!settings.tail_consumers || settings.tail_consumers.length === 0), 'settings');
  if (requireSecrets) requireThat(secretNames.every(name => seen.has(name)), 'secret');
}

export function settingsFieldClasses(settings, subdomain) {
  // Fixed classes only: no binding values, service names, identifiers or raw settings.
  const bindings = settings?.bindings;
  const validBinding = binding => binding && typeof binding.name === 'string' &&
    (binding.type === 'plain_text' && binding.name === 'ANTHROPIC_MODEL' && binding.text === 'claude-opus-4-8' ||
      binding.type === 'secret_text' && secretNames.includes(binding.name));
  const flag = value => value === undefined ? 'missing' : value === false ? 'disabled' :
    value === true ? 'enabled' : 'invalid';
  const observability = settings?.observability;
  return {
    bindings: Array.isArray(bindings) ? 'valid' : 'invalid',
    'binding-policy': !Array.isArray(bindings) ? 'unknown' : bindings.every(validBinding) ? 'matches' : 'conflict',
    'binding-names': !Array.isArray(bindings) ? 'unknown' :
      new Set(bindings.map(binding => binding?.name)).size === bindings.length ? 'unique' : 'duplicate',
    observability: observability === undefined ? 'absent' : observability === null ? 'null' :
      typeof observability !== 'object' || Array.isArray(observability) ? 'invalid' : flag(observability.enabled),
    logpush: settings?.logpush === undefined ? 'absent' : flag(settings.logpush),
    'tail-consumers': settings?.tail_consumers === undefined ? 'absent' :
      !Array.isArray(settings.tail_consumers) ? 'invalid' : settings.tail_consumers.length ? 'present' : 'empty',
    'workers-dev': flag(subdomain?.enabled),
    'preview-urls': flag(subdomain?.previews_enabled),
  };
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
      Array.isArray(actual[key]) && [...actual[key]].sort().join(',') === [...expected.ratelimit[key]].sort().join(',') :
      // Cloudflare's confirmed Free-plan response omits the optional all-requests default.
      key === 'requests_to_origin' && expected.ratelimit[key] === false ?
        actual[key] === undefined || actual[key] === false : actual[key] === expected.ratelimit[key]) &&
      !actual.counting_expression && !actual.score_per_period && !actual.score_response_header_name;
  }
  return !rule.ratelimit;
}

export function rateFieldClasses(rule) {
  // Every value is a fixed class. Never return a field value, identifier, expression or body.
  const classes = {};
  const exact = (actual, expected) => actual === undefined ? 'missing' : actual === expected ? 'matches' : 'mismatch';
  for (const field of ['ref', 'action', 'expression', 'enabled']) classes[field] = exact(rule?.[field], LIMIT[field]);
  classes.logging = rule?.logging === undefined ? 'absent' : rule.logging?.enabled === false ? 'disabled' :
    rule.logging?.enabled === true ? 'enabled' : 'invalid';
  classes['action-parameters'] = rule?.action_parameters === undefined ? 'absent' :
    rule.action_parameters && typeof rule.action_parameters === 'object' && !Array.isArray(rule.action_parameters) ?
      Object.keys(rule.action_parameters).length === 0 ? 'empty-default' : 'present' : 'invalid';
  const rate = rule?.ratelimit;
  classes.characteristics = !Array.isArray(rate?.characteristics) ? 'missing-or-invalid' :
    [...rate.characteristics].sort().join(',') === [...LIMIT.ratelimit.characteristics].sort().join(',') ? 'matches' : 'mismatch';
  for (const [label, field] of [['period', 'period'], ['requests', 'requests_per_period'], ['mitigation', 'mitigation_timeout']]) {
    classes[label] = exact(rate?.[field], LIMIT.ratelimit[field]);
  }
  classes['requests-to-origin'] = rate?.requests_to_origin === undefined ? 'absent-default' :
    rate.requests_to_origin === false ? 'matches' : rate.requests_to_origin === true ? 'mismatch' : 'invalid';
  classes['counting-expression'] = rate?.counting_expression === undefined ? 'absent-default' :
    rate.counting_expression === '' ? 'empty-default' : typeof rate.counting_expression === 'string' ? 'present' : 'invalid';
  classes['score-per-period'] = rate?.score_per_period === undefined ? 'absent' : rate.score_per_period === 0 ? 'zero-default' :
    typeof rate.score_per_period === 'number' ? 'present' : 'invalid';
  classes['score-response-header'] = rate?.score_response_header_name === undefined ? 'absent' :
    rate.score_response_header_name === '' ? 'empty-default' : typeof rate.score_response_header_name === 'string' ? 'present' : 'invalid';
  const metadata = ['id', 'version', 'ref', 'description', 'last_updated', 'action', 'expression', 'enabled',
    'logging', 'action_parameters', 'ratelimit', 'position'];
  classes['extra-rule-fields'] = rule && Object.keys(rule).some(key => !metadata.includes(key)) ? 'unexpected' : 'none';
  const allowedRate = [...Object.keys(LIMIT.ratelimit), 'counting_expression', 'score_per_period', 'score_response_header_name'];
  classes['extra-rate-fields'] = rate && Object.keys(rate).some(key => !allowedRate.includes(key)) ? 'unexpected' : 'none';
  return classes;
}

function firstRateDivergence(rule, fields) {
  for (const field of ['ref', 'action', 'expression', 'enabled']) if (fields[field] !== 'matches') return field;
  if (rule.logging?.enabled) return 'logging';
  if (rule.action_parameters) return 'action-parameters';
  for (const field of ['characteristics', 'period', 'requests', 'mitigation']) {
    if (fields[field] !== 'matches') return field;
  }
  if (!['matches', 'absent-default'].includes(fields['requests-to-origin'])) return 'requests-to-origin';
  if (rule.ratelimit.counting_expression) return 'counting-expression';
  if (rule.ratelimit.score_per_period) return 'score-per-period';
  if (rule.ratelimit.score_response_header_name) return 'score-response-header';
  return 'none';
}

export function rulesetInvariant(ruleset, phase) {
  if (ruleset === null) return 'ok';
  if (!ruleset || typeof ruleset !== 'object') return 'ruleset-shape';
  if (!id(ruleset.id)) return 'ruleset-identity';
  if (ruleset.kind !== 'zone') return 'kind';
  if (ruleset.phase !== phase) return 'phase';
  if (!Array.isArray(ruleset.rules)) return 'rules-array';
  if (ruleset.rules.some(rule => !id(rule.id))) return 'rule-identity';
  if (ruleset.rules.some(rule => rule.action === 'skip')) return 'skip';
  if (ruleset.rules.some(rule => rule.logging?.enabled)) return 'logging';
  const expected = phase === CUSTOM ? [HOLD, BOUNDARY] : [LIMIT];
  if (!expected.every(rule => ruleset.rules.filter(actual => actual.ref === rule.ref).length <= 1)) return 'duplicate-ref';
  for (const rule of expected) {
    const actual = ruleset.rules.find(candidate => candidate.ref === rule.ref);
    if (actual && !ruleMatches(actual, rule, rule.ref === HOLD.ref)) return 'owned-semantics';
  }
  // Never consume an unrelated rule slot or purchase capacity, regardless of zone plan.
  if (phase === RATE && !ruleset.rules.every(rule => rule.ref === LIMIT.ref)) return 'rate-capacity';
  return 'ok';
}

function checkRuleset(ruleset, phase) {
  requireThat(rulesetInvariant(ruleset, phase) === 'ok', 'rules');
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

function inspectRuleset(ruleset, phase, report) {
  const label = phase === CUSTOM ? 'custom' : 'rate';
  const expected = phase === CUSTOM ? [HOLD, BOUNDARY] : [LIMIT];
  report(`inspect: ${label} phase ${ruleset === null ? 'absent' : ruleset?.phase === phase ? 'matches' : 'mismatch'}`);
  report(`inspect: ${label} invariant ${rulesetInvariant(ruleset, phase)}`);
  const rules = Array.isArray(ruleset?.rules) ? ruleset.rules : null;
  report(`inspect: ${label} rules-list ${ruleset === null ? 'absent' : rules === null ? 'omitted-or-invalid' : rules.length ? 'populated' : 'empty'}`);
  for (const rule of expected) {
    const name = rule.ref === HOLD.ref ? 'hold' : rule.ref === BOUNDARY.ref ? 'boundary' : 'rate';
    const matches = rules?.filter(actual => actual.ref === rule.ref);
    const state = ruleset === null ? 'absent' : matches === undefined ? 'unknown' :
      matches.length === 0 ? 'absent' : matches.length > 1 ? 'conflict' :
      matches[0].enabled === true ? 'enabled' : matches[0].enabled === false ? 'disabled' : 'unknown';
    report(`inspect: owned ${name} ${state}`);
  }
  const unrelated = rules?.filter(rule => !expected.some(owned => owned.ref === rule.ref));
  report(`inspect: unrelated ${label} rules ${ruleset === null ? 'none' : unrelated === undefined ? 'unknown' : unrelated.length ? 'present' : 'none'}`);
  const required = rules?.length + expected.filter(owned => !rules?.some(rule => rule.ref === owned.ref)).length;
  report(`inspect: ${label} capacity ${ruleset === null ? 'available' : rules === null ? 'unknown' :
    required > (phase === CUSTOM ? 5 : 1) ? 'conflict' : 'available'}`);
  if (phase === RATE) {
    const owned = rules?.filter(rule => rule.ref === LIMIT.ref);
    if (owned?.length === 1) {
      const fields = rateFieldClasses(owned[0]);
      for (const [field, state] of Object.entries(fields)) report(`inspect: rate field ${field} ${state}`);
      report(`inspect: rate first divergence ${firstRateDivergence(owned[0], fields)}`);
    }
  }
}

export async function inspect({ cf, report = () => {} }) {
  requireThat(cf.readOnly === true, 'scope');
  const accounts = await cf.accountRequest('/accounts');
  requireThat(Array.isArray(accounts) && accounts.length === 1 && id(accounts[0].id), 'account');
  cf.account = accounts[0].id;
  const zones = await cf.accountRequest(`/zones?name=${TARGET.zone}&account.id=${cf.account}&status=active`);
  requireThat(Array.isArray(zones) && zones.length === 1 && zones[0].name === TARGET.zone &&
    zones[0].status === 'active' && zones[0].account?.id === cf.account && id(zones[0].id), 'zone');
  requireThat(/^Free(?:\b|\s)/i.test(zones[0].plan?.name ?? ''), 'rate-plan');
  cf.setScope(cf.account, zones[0].id);
  report('inspect: account single approved'); report('inspect: zone active approved Free');
  // GET raw phase entrypoints without changing or normalizing them. Report only fixed classes.
  const custom = await cf.zoneRequest(`/rulesets/phases/${CUSTOM}/entrypoint`, 'GET', undefined, true);
  const rate = await cf.zoneRequest(`/rulesets/phases/${RATE}/entrypoint`, 'GET', undefined, true);
  inspectRuleset(custom, CUSTOM, report); inspectRuleset(rate, RATE, report);
  const scripts = await cf.accountRequest(`/accounts/${cf.account}/workers/scripts`);
  requireThat(Array.isArray(scripts) && scripts.filter(script => script.id === TARGET.worker).length <= 1, 'target');
  const exists = scripts.some(script => script.id === TARGET.worker);
  report(`inspect: worker ${exists ? 'present' : 'absent'}`);
  if (exists) {
    const worker = `/accounts/${cf.account}/workers/scripts/${TARGET.worker}`;
    const settings = await cf.accountRequest(worker + '/settings');
    const subdomain = await cf.accountRequest(worker + '/subdomain');
    for (const [field, state] of Object.entries(settingsFieldClasses(settings, subdomain))) {
      report(`inspect: settings field ${field} ${state}`);
    }
    let settingsState = 'ok'; try { checkSettings(settings); } catch { settingsState = 'conflict'; }
    report(`inspect: settings invariant ${settingsState}`);
    const secrets = await cf.accountRequest(`/accounts/${cf.account}/workers/scripts/${TARGET.worker}/secrets`);
    requireThat(Array.isArray(secrets), 'secret');
    report(`inspect: provider binding ${secrets.some(secret => secret.name === 'OPENAI_API_KEY') ? 'present' : 'absent'}`);
    report(`inspect: client-gate binding ${secrets.some(secret => secret.name === 'CLIENT_SHARED_SECRET') ? 'present' : 'absent'}`);
    report(`inspect: unexpected secret bindings ${secrets.some(secret => !secretNames.includes(secret.name)) ? 'present' : 'absent'}`);
  } else {
    report('inspect: provider binding absent'); report('inspect: client-gate binding absent');
    report('inspect: unexpected secret bindings absent');
  }
  const domains = await cf.accountRequest(`/accounts/${cf.account}/workers/domains`);
  requireThat(Array.isArray(domains), 'route');
  let domain = 'conflict';
  try { domain = checkDomains(domains, cf.account, cf.zone) ? 'approved' : 'absent'; } catch {}
  report(`inspect: domain ${domain}`);
  const routes = await cf.accountRequest(`/zones/${cf.zone}/workers/routes`);
  let route = 'conflict'; try { checkRoutes(routes); route = 'clear'; } catch {}
  report(`inspect: legacy route ${route}`);
  report('inspected: read-only production state; no mutations or model calls');
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
  const stages = ['missing-authorization', 'wrong-authorization', 'correct-authorization'];
  for (const [index, authorization] of [null, 'Bearer deliberately-invalid-coach-gate', `Bearer ${gate}`].entries()) {
    let response;
    let failure = 'request', status = null, redirected = 'unknown', contract = 'not-read';
    try {
      response = await fetchImpl(TARGET.origin, {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(15_000),
        headers: { 'Content-Type': 'application/json', ...(authorization ? { Authorization: authorization } : {}) },
        body: '{',
      });
      status = Number.isInteger(response.status) && response.status >= 100 && response.status <= 599 ? response.status : null;
      redirected = response.redirected === true ? 'yes' : response.redirected === false ? 'no' : 'unknown';
      const expected = authorization === `Bearer ${gate}` ? 400 : 401;
      failure = 'body';
      if (!response.body) contract = 'body-unavailable';
      const bytes = await boundedBody(response, 8192, () => { failure = 'size'; contract = 'oversized'; });
      failure = 'json'; contract = 'non-json';
      const body = JSON.parse(bytes);
      contract = body?.error === 'unauthorized' ? 'unauthorized' : typeof body?.error === 'string' ? 'string-error' : 'invalid-error';
      failure = response.redirected ? 'redirect' : response.status !== expected ? 'status' : 'contract';
      requireThat(!response.redirected && response.status === expected &&
        (expected === 401 ? body.error === 'unauthorized' : typeof body.error === 'string'), 'gate');
    } catch (cause) {
      if (cause?.name === 'TimeoutError' || cause?.name === 'AbortError') failure = 'timeout';
      const error = new DeploymentFailure('gate');
      // No request/response content, headers, URL, identifier or exception survives this boundary.
      error.gateDiagnostic = Object.freeze({ stage: stages[index], failure, status, redirected, contract });
      throw error;
    }
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
  requireThat(process.argv.length === 3 && ['--deploy', '--inspect'].includes(process.argv[2]) && !process.stdin.isTTY, 'input');
  const readOnly = process.argv[2] === '--inspect';
  const repository = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
  let bytes = Buffer.alloc(0);
  for await (const chunk of process.stdin) {
    requireThat(bytes.length + chunk.length <= 4096, 'input');
    const next = Buffer.concat([bytes, chunk]); bytes.fill(0); bytes = next;
  }
  let packet;
  try {
    packet = JSON.parse(bytes.toString('utf8'));
    if (readOnly) packet = inspectionCredentialsFromPacket(packet);
    else packet = credentialsFromPacket(packet);
  }
  catch { throw new DeploymentFailure('input'); }
  finally { bytes.fill(0); }
  const oauth = await readWranglerOAuth();
  const cf = new Cloudflare(oauth, packet.wafToken, fetch, { readOnly });
  if (readOnly) return inspect({ cf, report: line => process.stdout.write(`${line}\n`) });
  await deploy({ cf, credentials: packet, stageWorker: account => stageWithWrangler(repository, account, oauth),
    report: line => process.stdout.write(`${line}\n`), probe: gateProbes });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => {
    const codes = new Set(['input', 'auth', 'account', 'zone', 'target', 'scope', 'rules', 'route',
      'settings', 'secret', 'wrangler', 'http', 'gate', 'rate-plan']);
    const code = error instanceof DeploymentFailure && codes.has(error.code) ? error.code : 'unexpected';
    const diagnostic = gateFailureLine(error);
    if (diagnostic) process.stdout.write(`${diagnostic}\n`);
    process.stdout.write(`blocked: ${code}\n`);
    process.exitCode = 78;
  });
}
