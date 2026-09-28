// Offline evaluation of the exact pinned transform, never Wrangler main or tail.
// Run in a dedicated Node process: the capability guards intentionally stay installed.
const fs = require('node:fs'), path = require('node:path'), Module = require('node:module');
const { fileURLToPath } = require('node:url');
const { transform } = require('./coach-tail-ready.cjs');
const root = path.resolve(__dirname, '..');
const dependencies = path.join(root, 'proxy/node_modules');
const file = path.join(dependencies, 'wrangler/wrangler-dist/cli.js');
const source = transform(fs.readFileSync(file, 'utf8'));
const output = process.stdout.write.bind(process.stdout);
const counts = { network: 0, child: 0, file: 0, write: 0, output: 0 };
const deny = kind => () => { counts[kind]++; throw Error('offline capability denied'); };

// No inherited credential environment; no real home directory is consulted.
// Wrangler eagerly calls getAuthTokens() during import. A synthetic env token
// takes its no-file branch; empty env would attempt config/default.toml, catch
// the denied read, and misleadingly appear to initialize successfully.
process.env = { WRANGLER_SEND_METRICS: 'false', CLOUDFLARE_API_TOKEN: 'offline-synthetic-token' };
const home = path.join(root, '.offline-tail-home');
require('node:os').homedir = () => home;
for (const [name, methods] of Object.entries({
  http: ['request', 'get'], https: ['request', 'get'],
  net: ['connect', 'createConnection'], tls: ['connect'], dgram: ['createSocket'],
  dns: ['lookup', 'resolve'], http2: ['connect'],
})) {
  const api = require('node:' + name);
  for (const method of methods) api[method] = deny('network');
}
require('node:net').Socket.prototype.connect = deny('network');
require('node:net').Server.prototype.listen = deny('network');
globalThis.fetch = deny('network');
for (const method of ['spawn', 'spawnSync', 'exec', 'execSync', 'execFile', 'execFileSync', 'fork']) {
  require('node:child_process')[method] = deny('child');
}
require('node:worker_threads').Worker = deny('child');

const resolve = value => path.resolve(value instanceof URL ? fileURLToPath(value) : String(value));
const isDependency = value => resolve(value).startsWith(dependencies + path.sep);
const missing = () => { throw Object.assign(Error('synthetic absent file'), { code: 'ENOENT' }); };
function checkRead(value) {
  if (!isDependency(value)) deny('file')();
}
for (const method of ['readFileSync', 'openSync', 'readFile', 'open', 'createReadStream']) {
  const original = fs[method];
  fs[method] = function(value, ...args) {
    // Bundled is-wsl probes this at import on Linux. Never read host procfs.
    if (method === 'readFileSync' && value === '/proc/version') return 'Linux offline fixture';
    checkRead(value);
    if (method.startsWith('open') && args[0] !== 'r') deny('write')();
    return original.call(this, value, ...args);
  };
}
for (const method of ['readFile', 'open']) {
  const original = fs.promises[method];
  fs.promises[method] = async function(value, ...args) {
    checkRead(value);
    if (method === 'open' && args[0] !== 'r') deny('write')();
    return original.call(this, value, ...args);
  };
}
// Non-dependency metadata is synthetic absence, including home/config discovery.
for (const method of ['statSync', 'lstatSync', 'realpathSync', 'readdirSync', 'accessSync', 'existsSync']) {
  const original = fs[method];
  fs[method] = function(value, ...args) {
    if (!isDependency(value)) return method === 'existsSync' ? false : missing();
    return original.call(this, value, ...args);
  };
}
for (const method of ['writeFile', 'appendFile', 'mkdir', 'mkdtemp', 'rm', 'rmdir', 'unlink',
  'rename', 'copyFile', 'cp', 'truncate', 'chmod', 'chown', 'link', 'symlink', 'utimes', 'write']) {
  for (const name of [method, method + 'Sync']) if (fs[name]) fs[name] = deny('write');
  if (fs.promises[method]) fs.promises[method] = deny('write');
}
fs.createWriteStream = deny('write');
for (const channel of [process.stdout, process.stderr]) channel.write = () => { counts.output++; return true; };

// Positive controls use only synthetic paths/arguments and hit guards before IO.
let guards = true;
for (const [kind, attempt] of [
  ['file', () => fs.readFileSync(path.join(home, 'config/default.toml'))],
  ['network', () => globalThis.fetch('https://offline.invalid')],
  ['child', () => require('node:child_process').execFileSync('offline-never-executed')],
  ['write', () => fs.writeFileSync(path.join(home, 'never-written'), '')],
]) {
  try { attempt(); guards = false; } catch { guards &&= counts[kind] === 1; }
  counts[kind] = 0;
}

let compiled = false, entrypoint = 'not_evaluated';
try {
  const m = new Module(file, module);
  m.filename = file;
  m.paths = Module._nodeModulePaths(path.dirname(file));
  m._compile(source, file);
  compiled = true;
  entrypoint = typeof m.exports.coachTailMain;
} catch { /* Fixed result only; never emit the caught dependency exception. */ }
const passed = guards && compiled && entrypoint === 'function' && Object.values(counts).every(n => n === 0);
output(JSON.stringify({ offline: true, synthetic_auth: true, main_invoked: false,
  guards, compiled, entrypoint, counts, passed }) + '\n');
process.exitCode = passed ? 0 : 78;
