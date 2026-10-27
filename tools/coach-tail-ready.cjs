// Reviewed Wrangler 4.154.0 adapter. Transform in memory; never edit the package.
const fs = require('node:fs'), path = require('node:path'), Module = require('node:module');
const crypto = require('node:crypto'), vm = require('node:vm');
const file = path.resolve(__dirname, '../proxy/node_modules/wrangler/wrangler-dist/cli.js');
const digest = '8dab269b2b490df04d1aeac0858a8d56af494b4144bcb4b66171b41d114cf88b';
const marker = '__COACH_TAIL_ATTACHED__';
function replaceOnce(source, needle, replacement) {
  if (source.split(needle).length !== 2) throw Error();
  return source.replace(needle, replacement);
}
function transform(source) {
  if (crypto.createHash('sha256').update(source).digest('hex') !== digest) throw Error();
  // Attached: the tail WebSocket has opened, just before its keep-alive ping starts.
  const attach = '          cancelPing = startWebSocketPing(tail, scheduleReconnect);';
  // One subscription: Wrangler 4 replaces a lost tail with new ones. With no attempts, a lost
  // connection deletes the tail and exits with an error, as Wrangler 3 did.
  const reconnect = '    MAX_RECONNECT_ATTEMPTS = RECONNECT_BACKOFF_MS.length;';
  const changed = replaceOnce(replaceOnce(source, attach, `          process.stdout.write("${marker}\\n");\n${attach}`),
    reconnect, '    MAX_RECONNECT_ATTEMPTS = 0;')
    // Exported for the adapter; the bundle's own export list omits main.
    + '\nmodule.exports.coachTailMain = main;';
  new vm.Script(changed, { filename: file });
  return changed;
}
module.exports = { transform, marker };
if (require.main === module) {
  try {
    const source = transform(fs.readFileSync(file, 'utf8'));
    if (process.argv.length === 3 && process.argv[2] === '--self-check') {
      process.stdout.write('tail-adapter verified=true live_session=false\n');
    } else {
      const version = process.argv[2];
      if (process.argv.length !== 3 || !/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(version || '')) throw Error();
      const m = new Module(file, module); m.filename = file; m.paths = Module._nodeModulePaths(path.dirname(file));
      m._compile(source, file);
      // No method/search/status filter: DO requests must remain observable. One exact version only.
      // No sampling filter: every event is sent, and Wrangler refuses a rate of 1 before creating a tail.
      // The default profile: a profile bound to this directory or a parent would otherwise win.
      m.exports.coachTailMain(['tail', 'reptoday-variety-language-proxy', '--format', 'json',
        '--version-id', version, '--profile', 'default']).catch(() => { process.exitCode = 78; });
    }
  } catch { process.stdout.write('tail-adapter verified=false\n'); process.exitCode = 78; }
}
