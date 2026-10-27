// Offline bundle check: every Wrangler configuration the proxy deploys from, built by the installed
// Wrangler (`deploy --dry-run --outdir`) the way the operator tools build it, must leave node:crypto to
// workerd's native module. Wrangler 3's nodejs_compat preset replaced createVerify/createSign/sign/
// verify with throwing unenv stubs, so every genuine App Attest assertion was rejected and the App
// Store Server API token could never be signed; Node-run tests could not see it. No deploy, login,
// Cloudflare request or network access: --dry-run stops before upload, the config home is private
// and npm's registry points at a closed local port.
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { basename, resolve } from 'node:path';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import { coachWorkerBuild, runtimeConfig } from '../../tools/coach-runtime-migrate.mjs';
import { stagingWorkerConfig, stagingTeardownConfig } from '../../tools/coach-staging.mjs';
import { stagingConfig } from '../../tools/coach-production-deploy.mjs';
import { nativeCryptoProblems } from './bundle-crypto.mjs';

// One offline Wrangler build of `config` (a JSON object, or the path of a committed config file).
// Returns the path of the built main module.
export async function wranglerBundle(root, config, dir) {
  await mkdir(dir, { recursive: true });
  let configPath = config, main;
  if (typeof config === 'string') main = /^main\s*=\s*"([^"]+)"/m.exec(await readFile(config, 'utf8'))[1];
  else { configPath = resolve(dir, 'wrangler.json'); main = config.main; await writeFile(configPath, JSON.stringify(config)); }
  // A private config home keeps the operator's Wrangler login unread; a closed local port keeps
  // Wrangler's best-effort update check offline. --dry-run never contacts Cloudflare.
  const env = { PATH: process.env.PATH, HOME: dir, XDG_CONFIG_HOME: dir, CI: 'true', NO_COLOR: '1',
    WRANGLER_SEND_METRICS: 'false', WRANGLER_LOG_PATH: resolve(dir, 'wrangler.log'), npm_config_registry: 'http://127.0.0.1:9/' };
  const result = spawnSync(process.execPath, [resolve(root, 'proxy/node_modules/wrangler/bin/wrangler.js'), 'deploy', '--dry-run',
    '--outdir', resolve(dir, 'dist'), '--config', configPath], { cwd: resolve(root, 'proxy'), env, encoding: 'utf8', timeout: 120_000 });
  assert.equal(result.status, 0, 'Wrangler could not bundle ' + basename(configPath));
  return resolve(dir, 'dist', basename(main));
}

export async function checkBundle(bundle, coach) {
  const problems = nativeCryptoProblems(await readFile(bundle, 'utf8'), { coach });
  assert.deepEqual(problems, [], `${bundle} does not reach workerd's native node:crypto`);
}

// Every deployable configuration, each from the factory or file its operator path uses.
export function deployableConfigs(root) {
  const revision = '0'.repeat(40);
  return [
    { name: 'wrangler.toml', config: resolve(root, 'proxy/wrangler.toml'), coach: false },
    { name: 'wrangler.runtime-auth.toml', config: resolve(root, 'proxy/wrangler.runtime-auth.toml'), coach: true },
    { name: 'production', config: runtimeConfig(root, revision, true, true), coach: true },
    { name: 'staging', config: stagingWorkerConfig(root, revision, 'https://reptoday-coach-staging.fixture.workers.dev/coach'), coach: true },
    { name: 'staging-teardown', config: stagingTeardownConfig(root), coach: false },
    { name: 'legacy-variety', config: stagingConfig(root), coach: false },
  ];
}

export async function checkDeployableBundles(root, output) {
  for (const { name, config, coach } of deployableConfigs(root))
    await checkBundle(await wranglerBundle(root, config, resolve(output, 'deployable', name)), coach);
  // Negative control through the real bundler: routing node:crypto back to unenv's polyfill, the
  // module Wrangler 3's preset served, must reintroduce the stubs and fail the check.
  const polyfill = createRequire(resolve(root, 'proxy/node_modules/wrangler/package.json')).resolve('unenv/node/crypto');
  const build = coachWorkerBuild(root);
  const stubbed = await wranglerBundle(root, { name: 'coach-local-test', main: resolve(root, 'proxy/src/coach-auth-worker.js'), ...build,
    alias: { ...build.alias, crypto: polyfill, 'node:crypto': polyfill }, workers_dev: false }, resolve(output, 'deployable', 'stubbed-control'));
  const problems = nativeCryptoProblems(await readFile(stubbed, 'utf8'), { coach: true });
  for (const api of ['createVerify', 'createSign', 'sign', 'verify'])
    assert.ok(problems.includes(`unenv stub notImplemented("crypto.${api}")`), 'negative control missed ' + api);
}
