import { describe, expect, test } from "vitest";
import { AppStoreVerificationError, decodeUnverifiedPayload, derFromBase64, verifyAppleSignedData } from "./appStoreJws";
import { APPLE_ROOT_CA_G2, APPLE_ROOT_CA_G3 } from "./appleRoots";
import { base64, base64Url, mintChain, signJws } from "./appStoreFixtures.testkit";

/**
 * The App Store signed-data verifier (M4, US-CA02), driven with real ECDSA signatures over a minted
 * Apple-shaped chain. Each refusal names the check that caught it, so a regression that silently
 * skips one check fails here rather than passing on a later one.
 */

const SIGNED_DATE = Date.UTC(2026, 10, 1);

async function expectReason(promise: Promise<unknown>, reason: string) {
  await expect(promise).rejects.toSatisfy((error: unknown) => error instanceof AppStoreVerificationError && error.reason === reason);
}

describe("verifyAppleSignedData", () => {
  test("returns the payload of a JWS signed by a chain that ends at a pinned root", async () => {
    const chain = await mintChain();
    const jws = await signJws({ signedDate: SIGNED_DATE, environment: "Sandbox" }, chain);
    await expect(verifyAppleSignedData(jws, { trustedRoots: [chain.rootDer] })).resolves.toEqual({
      signedDate: SIGNED_DATE,
      environment: "Sandbox",
    });
  });

  test("refuses a chain that ends at a root that is not pinned, even when it is self-consistent", async () => {
    const chain = await mintChain();
    const jws = await signJws({ signedDate: SIGNED_DATE }, chain);
    await expectReason(
      verifyAppleSignedData(jws, { trustedRoots: [derFromBase64(APPLE_ROOT_CA_G3), derFromBase64(APPLE_ROOT_CA_G2)] }),
      "untrusted_root",
    );
  });

  test("refuses a forged payload: the signature no longer matches", async () => {
    const chain = await mintChain();
    const jws = await signJws({ signedDate: SIGNED_DATE, environment: "Sandbox" }, chain);
    const [header, , signature] = jws.split(".");
    const forged = base64Url(new TextEncoder().encode(JSON.stringify({ signedDate: SIGNED_DATE, environment: "Production" })));
    await expectReason(verifyAppleSignedData(`${header}.${forged}.${signature}`, { trustedRoots: [chain.rootDer] }), "signature");
  });

  test("refuses a JWS signed by a key that is not the leaf's", async () => {
    const chain = await mintChain();
    const other = await mintChain();
    const jws = await signJws({ signedDate: SIGNED_DATE }, { ...chain, leafKey: other.leafKey });
    await expectReason(verifyAppleSignedData(jws, { trustedRoots: [chain.rootDer] }), "signature");
  });

  test("refuses a leaf that a different intermediate signed", async () => {
    const chain = await mintChain();
    const other = await mintChain();
    const jws = await signJws({ signedDate: SIGNED_DATE }, { ...chain, intermediateDer: other.intermediateDer });
    await expectReason(verifyAppleSignedData(jws, { trustedRoots: [chain.rootDer] }), "chain_signature");
  });

  test("refuses a leaf without Apple's App Store marker extension", async () => {
    const chain = await mintChain({ leafMarker: false });
    const jws = await signJws({ signedDate: SIGNED_DATE }, chain);
    await expectReason(verifyAppleSignedData(jws, { trustedRoots: [chain.rootDer] }), "marker_extension");
  });

  test("refuses an intermediate without Apple's WWDR marker extension", async () => {
    const chain = await mintChain({ intermediateMarker: false });
    const jws = await signJws({ signedDate: SIGNED_DATE }, chain);
    await expectReason(verifyAppleSignedData(jws, { trustedRoots: [chain.rootDer] }), "marker_extension");
  });

  test("refuses data signed outside the certificates' validity", async () => {
    const chain = await mintChain({ notBefore: new Date(Date.UTC(2027, 0, 1)), notAfter: new Date(Date.UTC(2030, 0, 1)) });
    const jws = await signJws({ signedDate: SIGNED_DATE }, chain);
    await expectReason(verifyAppleSignedData(jws, { trustedRoots: [chain.rootDer] }), "certificate_validity");
  });

  test("refuses a header that is not ES256 or carries the wrong number of certificates", async () => {
    const chain = await mintChain();
    await expectReason(verifyAppleSignedData(await signJws({}, chain, { alg: "HS256" }), { trustedRoots: [chain.rootDer] }), "algorithm");
    await expectReason(
      verifyAppleSignedData(await signJws({}, chain, { x5c: [base64(chain.leafDer), base64(chain.rootDer)] }), { trustedRoots: [chain.rootDer] }),
      "chain_shape",
    );
  });

  test("refuses malformed input before parsing anything", async () => {
    await expectReason(verifyAppleSignedData("not-a-jws", { trustedRoots: [] }), "malformed");
    await expectReason(verifyAppleSignedData("a.b.c.d", { trustedRoots: [] }), "malformed");
    await expectReason(verifyAppleSignedData("x".repeat(40_000), { trustedRoots: [] }), "malformed");
  });

  test("the pinned Apple roots decode to DER", () => {
    expect(derFromBase64(APPLE_ROOT_CA_G3).length).toBeGreaterThan(500);
    expect(derFromBase64(APPLE_ROOT_CA_G2).length).toBeGreaterThan(1000);
  });

  test("decodeUnverifiedPayload reads the claims without trusting them", async () => {
    const chain = await mintChain();
    const jws = await signJws({ environment: "Xcode" }, chain);
    expect(decodeUnverifiedPayload(jws)).toEqual({ environment: "Xcode" });
  });
});
