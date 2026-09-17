// Test-only entry: never referenced by either Wrangler deployment configuration.
import gateway, { CoachAuthenticationState } from '../src/coach-auth-worker.js';
import { assertKey, attestKey, premiumEntitlement, CoachAuthFailure } from '../src/coach-auth-crypto.js';
import {probeAppleAPI, probeAppleRequest} from './apple-api-probe.js';
// Tests seed a generated public key through a separate class, not a production enrollment bypass.
export class FixtureAuthenticationState extends CoachAuthenticationState {
  async fetch(request) {
    if (request.url === 'https://fixture-seed.invalid/') {
      const record = await request.json(); await this.ctx.storage.put('record', record);
      return new Response('seeded');
    }
    if (request.url === 'https://fixture-record.invalid/')
      return Response.json(await this.ctx.storage.get('record'));
    return super.fetch(request);
  }
}
export default { async fetch(request, env) {
  if (request.url.startsWith('https://runtime-fixture.invalid/')) {
    try {
      const input = await request.json();
      if (input.operation === 'assert') assertKey(Buffer.from(input.assertion, 'base64'), input.publicKey,
        input.previousCounter, Buffer.from(input.payload, 'base64'), input.prefix);
      else if (input.operation === 'attest') await attestKey(Buffer.from(input.attestation, 'base64'), input.keyId,
        input.challenge, input.prefix, Date.now());
      else if (input.operation === 'premium') await premiumEntitlement(input.jws, env);
      else if (input.operation === 'apple-request') return Response.json(await probeAppleRequest());
      else if (input.operation === 'apple-api' || input.operation === 'apple-response') {
        const result = await probeAppleAPI(input.privateKey, env, input.operation === 'apple-response', input.diagnose === true);
        return Response.json(result, {status: result.ok ? 200 : 401});
      }
      else throw new CoachAuthFailure();
      return new Response('verified');
    } catch (error) { return new Response(error instanceof CoachAuthFailure ? error.code : 'auth_unavailable', {status: 401}); }
  }
  return gateway.fetch(request, env);
}};
