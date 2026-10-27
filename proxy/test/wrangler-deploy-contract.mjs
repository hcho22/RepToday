// What the installed Wrangler sends when the operator tools deploy each Coach configuration, recorded
// against a local stand-in for the Cloudflare API. The real `wrangler deploy` runs with a private
// config home, a synthetic token and account, CLOUDFLARE_API_BASE_URL on 127.0.0.1 and npm's registry
// on a closed port: it can reach nothing else, and a request it sent elsewhere would carry no usable
// credential. It pins the upload the operator flows depend on, so a Wrangler upgrade that changes it
// fails here rather than in a live deploy. Live Cloudflare behavior stays a release check.
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { mkdir, rm, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { runtimeConfig, TAG, CLASS } from '../../tools/coach-runtime-migrate.mjs';
import { stagingWorkerConfig, stagingTeardownConfig, STAGING } from '../../tools/coach-staging.mjs';
import { TARGET } from '../../tools/coach-production-deploy.mjs';

const root = resolve('..');
const output = resolve('../build/coach-deploy-contract');
const account = 'f'.repeat(32);
const revision = '0'.repeat(40);
const origin = `https://${STAGING}.fixture.workers.dev/coach`;
const ok = result => ({ success: true, errors: [], messages: [], result });

function metadataOf(body, type) {
  const boundary = /boundary=(?:"([^"]+)"|([^;]+))/.exec(type);
  for (const part of body.toString('latin1').split('--' + (boundary[1] || boundary[2])))
    if (/name="metadata"/.test(part)) return JSON.parse(part.slice(part.indexOf('\r\n\r\n') + 4).replace(/\r\n$/, ''));
  return undefined;
}

// `existing`: the script's current migration tag on the stand-in, or null for no script.
async function deploy(name, config, existing) {
  const requests = [];
  const server = http.createServer((request, response) => {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.on('end', () => {
      const body = Buffer.concat(chunks), url = new URL(request.url, 'http://local');
      const path = url.pathname.replace('/client/v4', '').replace(account, 'ACCOUNT');
      const entry = { method: request.method, path, query: url.search };
      if (/multipart\/form-data/.test(request.headers['content-type'] ?? '')) entry.metadata = metadataOf(body, request.headers['content-type']);
      else if (body.length) entry.body = JSON.parse(body.toString());
      requests.push(entry);
      const script = /^\/accounts\/ACCOUNT\/workers\/(?:services|scripts|workers)\/([^/]+)/.exec(path)?.[1];
      let status = 200, payload = ok({});
      if (request.method === 'GET' && path === `/accounts/ACCOUNT/workers/services/${script}`) {
        if (existing === null) { status = 404; payload = { success: false, errors: [{ code: 10090, message: 'service not found' }], messages: [], result: null }; }
        else payload = ok({ default_environment: { environment: 'production', script: { migration_tag: existing } } });
      } else if (request.method === 'GET' && /\/(secrets|routes|domains)$/.test(path)) payload = ok([]);
      else if (request.method === 'GET' && path.endsWith('/deployments')) payload = ok({ deployments: [] });
      else if (request.method === 'GET' && path === `/accounts/ACCOUNT/workers/workers/${script}`)
        payload = ok({ subdomain: { enabled: false, previews_enabled: false } });
      else if (request.method === 'GET' && path === '/accounts/ACCOUNT/workers/subdomain') payload = ok({ subdomain: 'fixture' });
      else if (request.method === 'POST' && path.endsWith('/versions'))
        payload = ok({ id: '11111111-2222-4333-8444-555555555555', resources: { script: { etag: 'fixture' } }, startup_time_ms: 1 });
      else if (request.method === 'PUT' && path === `/accounts/ACCOUNT/workers/scripts/${script}`)
        payload = ok({ id: script, etag: 'fixture', deployment_id: '11111111-2222-4333-8444-555555555555', startup_time_ms: 1 });
      response.writeHead(status, { 'content-type': 'application/json' });
      response.end(JSON.stringify(payload));
    });
  });
  await new Promise(done => server.listen(0, '127.0.0.1', done));
  const dir = resolve(output, name);
  await rm(dir, { recursive: true, force: true }); await mkdir(dir, { recursive: true });
  const file = resolve(dir, 'wrangler.json');
  await writeFile(file, JSON.stringify(config));
  const env = { PATH: process.env.PATH, HOME: dir, XDG_CONFIG_HOME: dir, CI: 'true', NO_COLOR: '1', WRANGLER_SEND_METRICS: 'false',
    WRANGLER_LOG_PATH: resolve(dir, 'wrangler.log'), npm_config_registry: 'http://127.0.0.1:9/',
    CLOUDFLARE_API_BASE_URL: `http://127.0.0.1:${server.address().port}/client/v4`,
    CLOUDFLARE_API_TOKEN: 'local-synthetic-token', CLOUDFLARE_ACCOUNT_ID: account };
  let printed = '';
  try {
    const status = await new Promise((done, fail) => {
      const child = spawn(process.execPath, [resolve('node_modules/wrangler/bin/wrangler.js'), 'deploy', '--config', file],
        { cwd: resolve('.'), env, stdio: ['ignore', 'pipe', 'pipe'] });
      for (const stream of [child.stdout, child.stderr]) stream.on('data', chunk => { printed += chunk; });
      const timer = setTimeout(() => { child.kill('SIGKILL'); fail(new Error('wrangler deploy timed out: ' + name)); }, 120_000);
      child.on('close', code => { clearTimeout(timer); done(code); });
    });
    assert.equal(status, 0, `wrangler deploy failed against the local stand-in: ${name}\n${printed.slice(-2000)}`);
  } finally { server.close(); }
  // Reads are free; every write must be one of these, aimed at this script.
  const writes = requests.filter(entry => entry.method !== 'GET');
  const prefix = `/accounts/ACCOUNT/workers/scripts/${config.name}`;
  for (const write of writes)
    assert.ok([`POST ${prefix}/versions`, `POST ${prefix}/deployments`, `PATCH ${prefix}/script-settings`, `POST ${prefix}/subdomain`,
      `PUT ${prefix}`].includes(`${write.method} ${write.path}`), `${name}: unexpected ${write.method} ${write.path}`);
  return { writes, upload: writes.find(write => write.metadata)?.metadata };
}

const secretsKept = ['secret_text', 'secret_key'];
const immediate = { mode: 'immediate' };
const coachBindings = [{ name: 'COACH_AUTH_MODE', type: 'plain_text', text: 'app-attest-storekit-v1' },
  { name: 'COACH_AUTH_SOURCE_REV', type: 'plain_text', text: revision }];
const stateBinding = { name: 'COACH_AUTH_STATE', type: 'durable_object_namespace', class_name: CLASS };
const find = (writes, method, suffix) => writes.find(write => write.method === method && write.path.endsWith(suffix));

// Production release onto the existing Coach script: a new version at 100%, its Durable Object
// updated at once, secrets kept, logs and development URLs off, no migration and no dependency list.
{
  const { writes, upload } = await deploy('production', runtimeConfig(root, revision), TAG);
  assert.deepEqual(writes.map(write => `${write.method} ${write.path.split('/').pop()}`),
    ['POST versions', 'POST deployments', 'PATCH script-settings', `POST subdomain`]);
  assert.deepEqual(upload, { main_module: 'coach-auth-worker.js', bindings: [...coachBindings, stateBinding],
    compatibility_date: '2026-01-01', compatibility_flags: ['nodejs_compat'], keep_bindings: secretsKept,
    logpush: false, observability: { enabled: false } });
  assert.deepEqual(find(writes, 'POST', '/deployments').body, { strategy: 'percentage',
    versions: [{ version_id: '11111111-2222-4333-8444-555555555555', percentage: 100 }], annotations: {}, code_update_strategy: immediate });
  assert.deepEqual(find(writes, 'PATCH', '/script-settings').body, { logpush: false, observability: { enabled: false }, tags: [] });
  assert.deepEqual(find(writes, 'POST', '/subdomain').body, { enabled: false, previews_enabled: false });
  assert.ok(writes.every(write => write.path.includes(`/scripts/${TARGET.worker}`)));
}

// Staging deploy creates its own script with the SQLite class, on workers.dev only.
{
  const { writes, upload } = await deploy('staging', stagingWorkerConfig(root, revision, origin), null);
  assert.deepEqual(writes.map(write => `${write.method} ${write.path.split('/').pop()}`), [`PUT ${STAGING}`, 'POST subdomain']);
  assert.deepEqual(upload.migrations, { new_tag: TAG, steps: [{ new_sqlite_classes: [CLASS] }] });
  assert.deepEqual(upload.code_update_strategy, immediate);
  assert.deepEqual(upload.keep_bindings, secretsKept);
  assert.equal(upload.package_dependencies, undefined);
  assert.deepEqual(find(writes, 'POST', '/subdomain').body, { enabled: true, previews_enabled: false });
}

// Teardown of the deployed staging script uploads the one deletion step after TAG, as Wrangler 3 did.
{
  const { writes, upload } = await deploy('teardown', stagingTeardownConfig(root), TAG);
  assert.deepEqual(writes.map(write => `${write.method} ${write.path.split('/').pop()}`), [`PUT ${STAGING}`, 'POST subdomain']);
  assert.deepEqual(upload.migrations, { old_tag: TAG, new_tag: 'coach-security-teardown-v1', steps: [{ deleted_classes: [CLASS] }] });
  assert.deepEqual(upload.bindings, []);
  assert.deepEqual(upload.code_update_strategy, immediate);
}

// Orphaned-namespace recovery (no staging script): Wrangler 4 can only send the whole history, create
// then delete; Wrangler 3 sent the deletion alone. Which one Cloudflare accepts is a live check.
{
  const { upload } = await deploy('teardown-orphan', stagingTeardownConfig(root), null);
  assert.deepEqual(upload.migrations, { new_tag: 'coach-security-teardown-v1',
    steps: [{ new_sqlite_classes: [CLASS] }, { deleted_classes: [CLASS] }] });
}

console.log('validated: Wrangler deploy uploads for production, staging, teardown and orphan teardown against a local Cloudflare stand-in; no external request');
