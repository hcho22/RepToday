// Test-only Durable Object host: never referenced by either Wrangler deployment configuration.
// A separate workerd service gives the Durable Object its own isolate and clock, as production
// does when the Worker and its Durable Object run on different machines. Only this isolate's
// Date.now is shifted; the gateway isolate keeps the real clock.
import { FixtureAuthenticationState } from './workerd-auth-entry.js';

const systemNow = Date.now.bind(Date);
let lagMs = 0;
Date.now = () => systemNow() - lagMs;

export class SkewedAuthenticationState extends FixtureAuthenticationState {
  async fetch(request) {
    if (request.url === 'https://fixture-clock.invalid/') {
      const input = await request.json();
      if (!Number.isSafeInteger(input.lagMs)) return new Response('invalid lag', { status: 400 });
      lagMs = input.lagMs; return new Response('clock set');
    }
    return super.fetch(request);
  }
}
export default { fetch: () => new Response('not found', { status: 404 }) };
