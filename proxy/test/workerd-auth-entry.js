// Test-only entry: never referenced by either Wrangler deployment configuration.
import gateway, { CoachAuthenticationState } from '../src/coach-auth-worker.js';
import { assertKey, attestKey, premiumEntitlement, CoachAuthFailure } from '../src/coach-auth-crypto.js';
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
      else if (input.operation === 'apple-api') {
        const { AppStoreServerAPIClient, Environment } = await import('@apple/app-store-server-library');
        const client = new AppStoreServerAPIClient(input.privateKey, env.APP_STORE_KEY_ID, env.APP_STORE_ISSUER_ID,
          'com.reptoday.app', Environment.PRODUCTION);
        let result;
        try { result = await client.getAllSubscriptionStatuses('123'); }
        catch (error) {
          // Diagnostic classes only; never return the SDK message, generated JWT or input key.
          const message = String(error?.message ?? '');
          const kind = /Unexpected response body/.test(message) ? 'response-shape' :
            /not implemented|not supported/i.test(message) ? 'runtime-api' :
            /key|curve|ES256/i.test(message) ? 'key-signing' : 'transport';
          return new Response('test-api-failure:' + kind, {status: 401});
        }
        if (result.environment !== 'Production' || result.data.length !== 0) throw new CoachAuthFailure();
      }
      else throw new CoachAuthFailure();
      return new Response('verified');
    } catch (error) { return new Response(error instanceof CoachAuthFailure ? error.code : 'auth_unavailable', {status: 401}); }
  }
  return gateway.fetch(request, env);
}};
