// Test-only phase observations. Never returns SDK errors, JWTs, keys or response bodies.
export const appleApiFixture = {environment: 'Production', bundleId: 'com.reptoday.app', appAppleId: 1, data: []};
export const appleApiFixtureURL = 'https://api.storekit.apple.com/inApps/v1/subscriptions/123';

export async function probeAppleRequest() {
  const observations = [];
  const headers = {'X-Local-Fixture': 'response-only'};
  /** @type {Array<[string, string | URL, RequestInit]>} */
  const variants = [
    ['string', appleApiFixtureURL, {headers}],
    ['url', new URL(appleApiFixtureURL), {headers}],
    ['undefined-body', appleApiFixtureURL, {headers, method: 'GET', body: undefined}],
    ['redirect-error', appleApiFixtureURL, {headers, redirect: 'error'}],
    ['redirect-manual', appleApiFixtureURL, {headers, redirect: 'manual'}],
    ['timeout-signal', appleApiFixtureURL, {headers, signal: AbortSignal.timeout(2500)}],
    ['full', new URL(appleApiFixtureURL), {headers, method: 'GET', body: undefined,
      redirect: 'error', signal: AbortSignal.timeout(2500)}],
  ];
  for (const [variant, input, init] of variants) {
    let phase = 'request-construction';
    try {
      const request = new Request(input, init);
      phase = 'local-service-dispatch';
      const response = await fetch(request);
      phase = 'response-consumption';
      await response.arrayBuffer();
      observations.push({variant, ok: response.ok, phase: 'complete'});
    } catch {observations.push({variant, ok: false, phase});}
  }
  return observations;
}

export async function probeAppleAPI(privateKey, env, responseOnly = false, observeFetch = false, targetEnvironment = 'Production') {
  let phase = 'sdk-construction';
  const originalFetch = globalThis.fetch;
  try {
    if (observeFetch) globalThis.fetch = async (input, init) => {
      phase = 'local-service-dispatch';
      const response = await originalFetch(input, init);
      phase = 'response-adaptation';
      return new Proxy(response, {get(target, property) {
        if (property === 'body' && target.body) return new Proxy(target.body, {get(body, name) {
          if (name === 'getReader') return () => {phase = 'response-consumption'; return body.getReader();};
          const value = Reflect.get(body, name, body);
          return typeof value === 'function' ? value.bind(body) : value;
        }});
        const value = Reflect.get(target, property, target);
        return typeof value === 'function' ? value.bind(target) : value;
      }});
    };
    if (responseOnly) {
      const response = await globalThis.fetch(appleApiFixtureURL, {headers: {'X-Local-Fixture': 'response-only'}});
      const reader = response.body.getReader();
      while (!(await reader.read()).done) { /* consume synthetic bytes without emitting them */ }
      reader.releaseLock();
      return {ok: response.ok, phase: 'complete'};
    }
    const {AppStoreServerAPIClient, Environment} = await import('@apple/app-store-server-library');
    const selectedEnvironment = targetEnvironment === 'Production' ? Environment.PRODUCTION :
      targetEnvironment === 'Sandbox' ? Environment.SANDBOX : null;
    if (selectedEnvironment === null) throw new Error('unsupported fixture environment');
    const client = new AppStoreServerAPIClient(privateKey, env.APP_STORE_KEY_ID, env.APP_STORE_ISSUER_ID,
      'com.reptoday.app', selectedEnvironment);
    // SDK 3.1.0 exposes these methods at runtime but declares them protected/private in its types.
    // Observe the pinned implementation without replacing signing, request or decoding behavior.
    const observed = /** @type {any} */ (client);
    const sign = observed.createBearerToken.bind(client);
    observed.createBearerToken = () => {
      phase = 'jwt-signing';
      const token = sign();
      phase = 'request-adaptation';
      return token;
    };
    const request = observed.makeFetchRequest.bind(client);
    observed.makeFetchRequest = async (...args) => {
      phase = 'request-adaptation';
      const response = await request(...args);
      const json = response.json.bind(response);
      response.json = async () => {
        phase = 'response-json-decoding';
        const body = await json();
        phase = 'sdk-response-decoding';
        return body;
      };
      return response;
    };
    const result = await client.getAllSubscriptionStatuses('123');
    return {ok: result.environment === targetEnvironment && Array.isArray(result.data) && result.data.length === 0,
      phase: 'complete'};
  } catch { return {ok: false, phase}; }
  finally {globalThis.fetch = originalFetch;}
}
