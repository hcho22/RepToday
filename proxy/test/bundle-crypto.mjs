// What a Wrangler-built bundle must show to reach workerd's native node:crypto (wrangler-bundles.mjs
// builds them). Pure and dependency-free so the unit tests and the typecheck see only this rule.

// The crypto APIs the Coach Worker reaches: node-app-attest verifies assertions with createVerify,
// and the App Store Server API client signs its JWT through jwa's require('crypto').createSign.
const STUB = /notImplemented(?:Class)?\(\s*["'`]crypto\.[\w.]*["'`]\s*\)/g;
const POLYFILL = /unenv\/dist\/runtime\/node\/(?:internal\/)?crypto/;
const NATIVE_IMPORT = /^import\s+([^;]+?)\s+from\s*["'](?:node:)?crypto["'];?$/gm;

// Problems in one built bundle; empty means it reaches workerd's native node:crypto. `coach` marks a
// bundle of the Coach gateway, which must import createVerify and the default module (for the
// CommonJS require that jwa's createSign comes from) from the runtime rather than from a polyfill.
export function nativeCryptoProblems(source, { coach }) {
  const problems = [...new Set(source.match(STUB) ?? [])].map(stub => `unenv stub ${stub}`);
  if (POLYFILL.test(source)) problems.push('unenv crypto polyfill bundled');
  if (coach) {
    const imports = [...source.matchAll(NATIVE_IMPORT)].map(match => match[1]);
    if (!imports.some(binding => /^\{[^}]*\bcreateVerify\b[^}]*\}$/.test(binding)))
      problems.push('createVerify is not imported from the runtime crypto module');
    if (!imports.some(binding => /^[A-Za-z_$][\w$]*(?:\s*,|$)/.test(binding)))
      problems.push('the CommonJS crypto module is not the runtime default export');
  }
  return problems;
}
