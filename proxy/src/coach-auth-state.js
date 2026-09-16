import { DurableObject } from 'cloudflare:workers';
import { Buffer } from 'node:buffer';
import { CoachAuthFailure, VERSION, verifyChallenge, hash, keyIDValid, attestKey, assertKey, fromBase64, assertionPayload } from './coach-auth-crypto.js';

export const RETENTION_MS = 30 * 24 * 60 * 60 * 1000;
const response = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
/** @typedef {{v?: string, publicKey?: string, counter?: number, expiresAt?: number,
 * pendingNonceHash?: string, pendingExpiresAt?: number, tombstoneUntil?: number}} SecurityRecord */

// No content, body/transaction hash, receipt, purchase ID or proof is stored. One <=2 KiB
// record/key, one pending nonce hash, and one alarm; namespace is production/protocol-specific.
export class CoachAuthenticationState extends DurableObject {
  async fetch(request) {
    try {
      if (request.method !== 'POST' || Number(request.headers.get('Content-Length')) > 24 * 1024) throw new CoachAuthFailure();
      const bytes = await readBounded(request, 24 * 1024);
      const input = JSON.parse(Buffer.from(bytes).toString('utf8'));
      if (!keyIDValid(input.keyId) || !/^[A-Z0-9]{10}$/.test(this.env.APP_ATTEST_APP_PREFIX ?? '')) throw new CoachAuthFailure();
      const now = Date.now();
      verifyChallenge(input.challenge, input.keyId, this.env.CLIENT_SHARED_SECRET, now);
      if (input.operation === 'enroll') {
        const attestation = fromBase64(input.attestation, 8192);
        // Full crypto verification precedes any storage allocation or enrollment write.
        const publicKey = await attestKey(attestation, input.keyId, input.challenge, this.env.APP_ATTEST_APP_PREFIX, now);
        await this.ctx.storage.transaction(async tx => {
          const current = /** @type {SecurityRecord} */ (await tx.get('record'));
          const commitNow = Date.now();
          verifyChallenge(input.challenge, input.keyId, this.env.CLIENT_SHARED_SECRET, commitNow);
          if (current && (current.expiresAt > commitNow || current.tombstoneUntil > commitNow)) throw new CoachAuthFailure();
          const record = { v: VERSION, publicKey, counter: 0, expiresAt: commitNow + RETENTION_MS };
          await tx.put('record', record); await tx.setAlarm(record.expiresAt);
        });
        return response({ enrolled: true });
      }
      if (input.operation === 'challenge') {
        await this.ctx.storage.transaction(async tx => {
          const record = /** @type {SecurityRecord} */ (await tx.get('record'));
          verifyChallenge(input.challenge, input.keyId, this.env.CLIENT_SHARED_SECRET, Date.now());
          if (!record || record.v !== VERSION || !record.publicKey || record.expiresAt <= Date.now()) throw new CoachAuthFailure('key_unavailable');
          record.pendingNonceHash = hash(input.challenge);
          record.pendingExpiresAt = now + 60_000;
          await tx.put('record', record); // Replaces an earlier pending challenge; iOS serializes the flow.
        });
        return response({ ready: true });
      }
      if (!['reply', 'delete'].includes(input.operation) || !/^[0-9a-f]{64}$/.test(input.bodyHash) ||
          !/^[0-9a-f]{64}$/.test(input.transactionHash)) throw new CoachAuthFailure();
      const assertion = fromBase64(input.assertion, 1024);
      await this.ctx.storage.transaction(async tx => {
        const record = /** @type {SecurityRecord} */ (await tx.get('record'));
        const commitNow = Date.now();
        verifyChallenge(input.challenge, input.keyId, this.env.CLIENT_SHARED_SECRET, commitNow);
        if (!record || record.v !== VERSION || !record.publicKey || record.expiresAt <= commitNow) throw new CoachAuthFailure('key_unavailable');
        if (record.pendingExpiresAt <= commitNow || record.pendingNonceHash !== hash(input.challenge)) throw new CoachAuthFailure();
        const payload = assertionPayload(input.operation, input.keyId, input.challenge, input.bodyHash, input.transactionHash);
        const counter = assertKey(assertion, record.publicKey, record.counter, payload, this.env.APP_ATTEST_APP_PREFIX);
        if (input.operation === 'delete') {
          // Captured still-valid enrollment cannot reset a counter immediately after deletion.
          const tombstoneUntil = commitNow + 60_000;
          await tx.put('record', { tombstoneUntil }); await tx.setAlarm(tombstoneUntil);
        } else {
          await tx.put('record', { v: VERSION, publicKey: record.publicKey, counter, expiresAt: commitNow + RETENTION_MS });
          await tx.setAlarm(commitNow + RETENTION_MS);
        }
      });
      return response({ authorized: true });
    } catch (error) {
      const code = error instanceof CoachAuthFailure ? error.code : 'auth_unavailable';
      return response({ error: code }, code === 'auth_unavailable' ? 503 : 401);
    }
  }

  async alarm() {
    await this.ctx.storage.transaction(async tx => {
      const record = /** @type {SecurityRecord} */ (await tx.get('record'));
      if (!record) return;
      const expiry = record.expiresAt ?? record.tombstoneUntil;
      if (Date.now() >= expiry) await tx.delete('record');
      else await tx.setAlarm(expiry);
    });
  }
}

export async function readBounded(request, maximum) {
  if (!request.body) throw new CoachAuthFailure();
  const reader = request.body.getReader(); const chunks = []; let size = 0;
  let timer;
  const expired = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new CoachAuthFailure('auth_unavailable')), 5_000);
  });
  try {
    while (true) {
      const { done, value } = await Promise.race([reader.read(), expired]); if (done) break;
      size += value.length;
      if (size > maximum) throw new CoachAuthFailure('payload_too_large');
      chunks.push(value);
    }
    return Buffer.concat(chunks);
  } finally { clearTimeout(timer); await reader.cancel().catch(() => {}); reader.releaseLock(); }
}
