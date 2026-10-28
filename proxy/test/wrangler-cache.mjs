// Wrangler's shared account cache is `node_modules/.cache/wrangler` in the nearest node_modules above its
// working directory, and Wrangler reads the account from it before asking the API. The Wrangler contracts
// plant a poisoned account there to prove the operator tools ignore it, and check that no run leaves a
// file in a shared cache.
import assert from 'node:assert/strict';
import { mkdir, readFile, readdir, rm, stat, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

export const poisonedAccount = 'e'.repeat(32);

// Every file in the two shared caches an operator run can reach: the repository root's node_modules (the
// tail capture runs under build/) and proxy/node_modules (the deploy runs in proxy/).
export async function sharedCaches(root) {
  const files = {};
  for (const dir of [resolve(root, 'node_modules/.cache/wrangler'), resolve(root, 'proxy/node_modules/.cache/wrangler')]) {
    let names = [];
    try { names = await readdir(dir); } catch (error) { if (error.code !== 'ENOENT') throw error; }
    for (const name of names.sort()) files[resolve(dir, name)] = await readFile(resolve(dir, name), 'utf8');
  }
  return files;
}

// Runs `run` with a poisoned wrangler-account.json in `modules`/.cache/wrangler, requires that the run left
// it untouched, then restores exactly what was there, removing any directory it had to create.
export async function withPoisonedCache(modules, run) {
  const dir = resolve(modules, '.cache/wrangler'), file = resolve(dir, 'wrangler-account.json');
  let created = null;
  for (let probe = dir; ; probe = dirname(probe)) {
    try { await stat(probe); break; } catch (error) { if (error.code !== 'ENOENT') throw error; created = probe; }
  }
  let previous = null;
  try { previous = await readFile(file, 'utf8'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const poisoned = JSON.stringify({ account: { id: poisonedAccount, name: 'Poisoned account' } });
  await mkdir(dir, { recursive: true });
  await writeFile(file, poisoned);
  try {
    const result = await run();
    assert.equal(await readFile(file, 'utf8'), poisoned, 'a run rewrote the shared account cache');
    return result;
  } finally {
    if (previous === null) await rm(file, { force: true });
    else await writeFile(file, previous);
    if (created) await rm(created, { recursive: true, force: true });
  }
}
