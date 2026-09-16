import { Buffer } from 'node:buffer';

// Wrangler/Vitest alias replaces the official Apple library's node-fetch transport only.
// Signature, chain, OCSP parsing and token generation remain in Apple's library.
export const Headers = globalThis.Headers;
export const Response = globalThis.Response;
export default async function appleFetch(input, options = {}) {
  const url = new URL(String(input).trim());
  const method = options.method ?? 'GET';
  // Pinned official SDK 3.1.0 uses this production origin (not the legacy iTunes host).
  const api = url.origin === 'https://api.storekit.apple.com' && !url.search &&
    /^\/inApps\/v1\/subscriptions\/[0-9]{1,32}$/.test(url.pathname) && method === 'GET';
  const ocsp = ['ocsp.apple.com', 'ocsp2.apple.com'].includes(url.hostname) &&
    ['http:', 'https:'].includes(url.protocol) && !url.port && method === 'POST';
  if ((!api && !ocsp) || url.username || url.password || url.hash) throw new Error('Apple verification unavailable');
  const response = await fetch(url, { ...options, redirect: 'error', signal: AbortSignal.timeout(2_500) });
  if (response.redirected || !response.body) throw new Error('Apple verification unavailable');
  const maximum = api ? 64 * 1024 : 16 * 1024;
  const reader = response.body.getReader();
  const chunks = []; let count = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      count += value.byteLength;
      if (count > maximum) throw new Error('Apple verification unavailable');
      chunks.push(value);
    }
  } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
  const bytes = Buffer.concat(chunks);
  // Compatibility surface consumed by Apple's SDK, with every body already bounded.
  return { ok: response.ok, status: response.status, headers: response.headers,
    json: async () => JSON.parse(bytes.toString('utf8')), text: async () => bytes.toString('utf8'),
    buffer: async () => Buffer.from(bytes), arrayBuffer: async () => Uint8Array.from(bytes).buffer };
}
