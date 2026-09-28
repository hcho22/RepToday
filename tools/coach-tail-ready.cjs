// Reviewed Wrangler 3.114.17 adapter. Transform in memory; never edit the package.
const fs = require('node:fs'), path = require('node:path'), Module = require('node:module');
const crypto = require('node:crypto'), vm = require('node:vm');
const file = path.resolve(__dirname, '../proxy/node_modules/wrangler/wrangler-dist/cli.js');
const digest = '3ddc7ba0e400b3ad75e49a4bb18dc9b6b6727873920efe4797940b67bdbb790a';
const marker = '__COACH_TAIL_ATTACHED__';
function transform(source) {
  if (crypto.createHash('sha256').update(source).digest('hex') !== digest) throw Error();
  const needle = '    const cancelPing = startWebSocketPing();';
  if (source.split(needle).length !== 2) throw Error();
  const changed = source.replace(needle, `    process.stdout.write("${marker}\\n");\n${needle}`)
    // Wrangler reassigns module.exports; the initial exports alias is stale.
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
      m.exports.coachTailMain(['tail', 'reptoday-variety-language-proxy', '--format', 'json',
        '--version-id', version, '--sampling-rate', '1']).catch(() => { process.exitCode = 78; });
    }
  } catch { process.stdout.write('tail-adapter verified=false\n'); process.exitCode = 78; }
}
