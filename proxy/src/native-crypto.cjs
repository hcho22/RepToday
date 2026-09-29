// The Coach Worker's `crypto`/`node:crypto` in every Wrangler bundle (alias in coachWorkerBuild,
// tools/coach-runtime-migrate.mjs): workerd's native module, whole. Wrangler 3's nodejs_compat preset
// otherwise swaps createVerify/createSign/sign/verify for throwing stubs, which failed every App Attest
// assertion (node-app-attest) and would fail App Store API JWT signing (jwa). getBuiltinModule reaches
// the runtime module directly, so this alias cannot resolve back to itself. CommonJS keeps every
// property reachable for both named ESM imports and require('crypto').
module.exports = globalThis.process.getBuiltinModule('node:crypto');
