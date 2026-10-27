import { describe, expect, it } from 'vitest';
import { nativeCryptoProblems } from './bundle-crypto.mjs';

// The real Wrangler builds run in test/workerd-auth.mjs; these pin what the check accepts and refuses.
const native = 'import { createHash as createHash2, createVerify } from "crypto";\nimport libDefault4 from "crypto";\n';

describe('the Wrangler bundle crypto check', () => {
  it('accepts a Coach bundle that imports createVerify and the CommonJS module from the runtime', () => {
    expect(nativeCryptoProblems(native, { coach: true })).toEqual([]);
    expect(nativeCryptoProblems(native.replaceAll('"crypto"', '"node:crypto"'), { coach: true })).toEqual([]);
  });

  it('refuses every unenv crypto stub Wrangler 3 bundled, function or class', () => {
    const stubbed = native + [
      'createVerify = /* @__PURE__ */ notImplemented("crypto.createVerify");',
      'createSign = /* @__PURE__ */ notImplemented("crypto.createSign");',
      'Verify = /* @__PURE__ */ notImplementedClass("crypto.Verify");',
    ].join('\n');
    expect(nativeCryptoProblems(stubbed, { coach: true })).toEqual([
      'unenv stub notImplemented("crypto.createVerify")',
      'unenv stub notImplemented("crypto.createSign")',
      'unenv stub notImplementedClass("crypto.Verify")',
    ]);
    expect(nativeCryptoProblems(stubbed, { coach: false })).toHaveLength(3);
  });

  it('refuses unenv\'s crypto polyfill even when no stub name survives minification', () => {
    expect(nativeCryptoProblems(native + '// node_modules/unenv/dist/runtime/node/internal/crypto/node.mjs\n', { coach: true }))
      .toEqual(['unenv crypto polyfill bundled']);
  });

  it('refuses a Coach bundle whose crypto no longer comes from the runtime', () => {
    expect(nativeCryptoProblems('import libDefault4 from "crypto";\n', { coach: true }))
      .toEqual(['createVerify is not imported from the runtime crypto module']);
    expect(nativeCryptoProblems('import { createVerify } from "crypto";\n', { coach: true }))
      .toEqual(['the CommonJS crypto module is not the runtime default export']);
    expect(nativeCryptoProblems('module.exports = globalThis.process.getBuiltinModule("node:crypto");\n', { coach: true }))
      .toHaveLength(2);
  });

  it('asks nothing of a bundle that does not reach crypto and ignores stubs outside crypto', () => {
    expect(nativeCryptoProblems('notImplemented("process.report.getReport");\n', { coach: false })).toEqual([]);
  });
});
