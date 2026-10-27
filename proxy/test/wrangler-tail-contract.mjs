// What the final-auth capture does with the installed Wrangler's real `tail`, recorded against a local
// stand-in for the Cloudflare tails API and its trace-v1 WebSocket. The committed capture
// (tools/coach-capture-guard-tail.py, spawning tools/coach-tail-ready.cjs) runs as the operator runs it,
// with a private config home holding synthetic logins, a synthetic account and CLOUDFLARE_API_BASE_URL
// on 127.0.0.1: it can reach nothing else. Live attachment to Cloudflare stays a release check.
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, rm, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const root = resolve('..');
const home = resolve('../build/coach-tail-contract');
const WORKER = 'reptoday-variety-language-proxy';
const VERSION = '0123abcd-4567-4890-abcd-0123456789ab';
const account = 'f'.repeat(32);
const ok = result => ({ success: true, errors: [], messages: [], result });
// The default login the capture must use, and another profile bound to build/, the parent of the
// capture's working directory, which Wrangler 4 would pick without the adapter's --profile default.
const login = 'default-profile-oauth-token';
const decoy = 'bound-profile-oauth-token';
const oauth = token => `oauth_token = "${token}"\nexpiration_time = "2999-01-01T00:00:00.000Z"\n`;
const guardRow = { event: 'coach_final_auth_guard', stage: 'do_assertion', reason: 'assertion_signature' };

const frame = (opcode, payload) => {
  const data = Buffer.from(payload);
  const head = data.length < 126 ? Buffer.from([0x80 | opcode, data.length])
    : Buffer.from([0x80 | opcode, 126, data.length >> 8, data.length & 255]);
  return Buffer.concat([head, data]);
};

// `closeAbnormally`: after the events, the stand-in drops the connection with 1011.
async function capture(closeAbnormally) {
  const requests = [];
  const server = http.createServer((request, response) => {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.on('end', () => {
      const body = Buffer.concat(chunks).toString();
      const path = new URL(request.url, 'http://local').pathname.replace('/client/v4', '').replace(account, 'ACCOUNT');
      requests.push({ method: request.method, path, login: request.headers.authorization, body: body ? JSON.parse(body) : undefined });
      let payload = ok({});
      if (request.method === 'POST' && path === `/accounts/ACCOUNT/workers/scripts/${WORKER}/tails`) {
        const id = `tail-${requests.filter(entry => entry.path === path).length}`;
        payload = ok({ id, url: `ws://127.0.0.1:${server.address().port}/${id}`, expires_at: new Date(Date.now() + 3_600_000).toISOString() });
      }
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify(payload));
    });
  });
  // Wrangler's tail client sends unmasked frames, which Cloudflare accepts and the ws server refuses.
  const sockets = [];
  server.on('upgrade', (request, socket) => {
    sockets.push(socket);
    const accept = createHash('sha1').update(request.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
    socket.write(['HTTP/1.1 101 Switching Protocols', 'Upgrade: websocket', 'Connection: Upgrade',
      `Sec-WebSocket-Accept: ${accept}`, 'Sec-WebSocket-Protocol: trace-v1', '', ''].join('\r\n'));
    const base = { scriptName: WORKER, scriptVersion: { id: VERSION }, outcome: 'ok', exceptions: [], logs: [] };
    let pending = Buffer.alloc(0), sent = false;
    socket.on('error', () => {});
    socket.on('data', chunk => {
      pending = Buffer.concat([pending, chunk]);
      while (pending.length >= 2) {
        const opcode = pending[0] & 15, masked = pending[1] & 128;
        let length = pending[1] & 127, offset = 2;
        if (length === 126) { length = pending.readUInt16BE(2); offset = 4; }
        const key = offset; if (masked) offset += 4;
        if (pending.length < offset + length) return;
        const payload = Buffer.from(pending.subarray(offset, offset + length).map((byte, i) => masked ? byte ^ pending[key + (i % 4)] : byte));
        pending = pending.subarray(offset + length);
        if (opcode === 9) socket.write(frame(10, payload));
        else if (opcode === 8) socket.end();
        // The client's first message is sent once the tail opens: Worker and Durable Object events follow.
        else if (opcode === 1 && !sent) {
          sent = true;
          for (const event of [{ ...base, entrypoint: 'default' }, { ...base, entrypoint: 'CoachAuthenticationState' },
            { ...base, entrypoint: 'CoachAuthenticationState', logs: [{ level: 'log', message: [JSON.stringify(guardRow)] }] }])
            socket.write(frame(1, JSON.stringify(event)));
          if (closeAbnormally) socket.end(frame(8, Buffer.concat([Buffer.from([1011 >> 8, 1011 & 255]), Buffer.from('stand-in')])));
        }
      }
    });
  });
  await new Promise(done => server.listen(0, '127.0.0.1', done));
  await rm(home, { recursive: true, force: true });
  await mkdir(resolve(home, '.wrangler/config'), { recursive: true });
  await mkdir(resolve(home, '.wrangler/profiles'));
  await writeFile(resolve(home, '.wrangler/config/default.toml'), oauth(login));
  await writeFile(resolve(home, '.wrangler/config/bound.toml'), oauth(decoy));
  await writeFile(resolve(home, '.wrangler/profiles/directory-bindings.json'), JSON.stringify({ [resolve(root, 'build')]: 'bound' }));
  const env = { PATH: `${dirname(process.execPath)}:${process.env.PATH}`, HOME: home, XDG_CONFIG_HOME: home, NO_COLOR: '1',
    CLOUDFLARE_API_BASE_URL: `http://127.0.0.1:${server.address().port}/client/v4`, CLOUDFLARE_ACCOUNT_ID: account };
  let printed = '';
  try {
    const status = await new Promise((done, fail) => {
      const child = spawn('python3', [resolve(root, 'tools/coach-capture-guard-tail.py'), '--capture-version', VERSION, '--seconds', '60'],
        { cwd: root, env, stdio: ['ignore', 'pipe', 'inherit'] });
      child.stdout.on('data', chunk => { printed += chunk; });
      const timer = setTimeout(() => { child.kill('SIGKILL'); fail(new Error('capture timed out')); }, 90_000);
      child.on('close', code => { clearTimeout(timer); done(code); });
    });
    return { status, output: printed.trim().split('\n').map(line => JSON.parse(line)), requests };
  } finally {
    for (const socket of sockets) socket.destroy();
    server.close();
    await rm(home, { recursive: true, force: true });
  }
}

const tails = requests => requests.filter(entry => entry.path.endsWith('/tails'));
const deletes = requests => requests.filter(entry => entry.method === 'DELETE');

// Attached, ready on Worker and Durable Object events, the one guard row, then the deadline the first
// row set. One tail on exactly the candidate version with no other filter, deleted at the end.
{
  const { status, output, requests } = await capture(false);
  assert.deepEqual(output, [{ capture: 'starting', ready: false }, { capture: 'attached', ready: false },
    { capture: 'ready', ready: true, coverage: 'worker_and_do' }, guardRow,
    { capture: 'ended', ready: true, reason: 'deadline', fixed_rows: 1, remote_closure: 'unverified' }]);
  assert.equal(status, 0);
  assert.deepEqual(tails(requests).map(entry => entry.body), [{ filters: [{ scriptVersion: VERSION }] }]);
  assert.deepEqual(deletes(requests).map(entry => entry.path), [`/accounts/ACCOUNT/workers/scripts/${WORKER}/tails/tail-1`]);
  assert.deepEqual([...new Set(requests.map(entry => entry.login))], [`Bearer ${login}`], 'the tail did not use the default login');
}

// A lost connection deletes the tail and ends the capture; it never opens a second subscription.
{
  const { status, output, requests } = await capture(true);
  assert.equal(status, 78);
  assert.deepEqual(output.at(-1), { capture: 'ended', ready: true, reason: 'child_exit', fixed_rows: 1, remote_closure: 'unverified' });
  assert.equal(tails(requests).length, 1);
  assert.equal(deletes(requests).length, 1);
}

console.log('validated: the final-auth capture attaches through the installed Wrangler tail against a local Cloudflare stand-in, on one version-filtered subscription and the default login despite a bound profile; no external request');
