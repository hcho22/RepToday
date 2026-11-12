import * as asn1js from "asn1js";
import * as pkijs from "pkijs";
import { APPLE_INTERMEDIATE_MARKER_OID, APPLE_LEAF_MARKER_OID } from "./appStoreJws";

/**
 * Test-only minting of App Store-shaped signed data (M4, US-CA02).
 *
 * Builds a throwaway root -> intermediate -> leaf chain with Apple's marker extensions and signs JWS
 * strings with the leaf, so the verifier and the entitlement boundary are tested against real
 * signatures rather than mocks. Keys live only in memory for one test run; nothing here is a secret.
 * The two-dot file name keeps the Convex bundler from deploying it (`convex/README.md`).
 */

export type TestChain = {
  rootDer: Uint8Array;
  intermediateDer: Uint8Array;
  leafDer: Uint8Array;
  leafKey: CryptoKey;
};

export type ChainOptions = {
  /** Omit Apple's leaf marker extension, to prove a non-App-Store leaf is refused. */
  leafMarker?: boolean;
  /** Omit Apple's intermediate marker extension. */
  intermediateMarker?: boolean;
  notBefore?: Date;
  notAfter?: Date;
};

const DAY_MS = 24 * 60 * 60 * 1000;

async function keyPair(curve: "P-256" | "P-384"): Promise<CryptoKeyPair> {
  return (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: curve }, true, ["sign", "verify"])) as CryptoKeyPair;
}

function name(commonName: string): pkijs.RelativeDistinguishedNames {
  return new pkijs.RelativeDistinguishedNames({
    typesAndValues: [new pkijs.AttributeTypeAndValue({ type: "2.5.4.3", value: new asn1js.Utf8String({ value: commonName }) })],
  });
}

function marker(oid: string): pkijs.Extension {
  return new pkijs.Extension({ extnID: oid, critical: false, extnValue: new asn1js.Null().toBER(false) });
}

async function certificate(options: {
  subject: string;
  issuer: string;
  serial: number;
  publicKey: CryptoKey;
  signingKey: CryptoKey;
  hash: "SHA-256" | "SHA-384";
  extensions: pkijs.Extension[];
  notBefore: Date;
  notAfter: Date;
}): Promise<Uint8Array> {
  const cert = new pkijs.Certificate();
  cert.version = 2;
  cert.serialNumber = new asn1js.Integer({ value: options.serial });
  cert.subject = name(options.subject);
  cert.issuer = name(options.issuer);
  cert.notBefore.value = options.notBefore;
  cert.notAfter.value = options.notAfter;
  if (options.extensions.length > 0) {
    cert.extensions = options.extensions;
  }
  await cert.subjectPublicKeyInfo.importKey(options.publicKey);
  await cert.sign(options.signingKey, options.hash);
  return new Uint8Array(cert.toSchema(true).toBER(false));
}

/** A fresh three-certificate chain shaped like Apple's App Store signing chain. */
export async function mintChain(options: ChainOptions = {}): Promise<TestChain> {
  const notBefore = options.notBefore ?? new Date(Date.UTC(2020, 0, 1));
  const notAfter = options.notAfter ?? new Date(Date.now() + 3650 * DAY_MS);
  const root = await keyPair("P-384");
  const intermediate = await keyPair("P-384");
  const leaf = await keyPair("P-256");
  const rootDer = await certificate({
    subject: "Test Root",
    issuer: "Test Root",
    serial: 1,
    publicKey: root.publicKey,
    signingKey: root.privateKey,
    hash: "SHA-384",
    extensions: [],
    notBefore,
    notAfter,
  });
  const intermediateDer = await certificate({
    subject: "Test WWDR",
    issuer: "Test Root",
    serial: 2,
    publicKey: intermediate.publicKey,
    signingKey: root.privateKey,
    hash: "SHA-384",
    extensions: options.intermediateMarker === false ? [] : [marker(APPLE_INTERMEDIATE_MARKER_OID)],
    notBefore,
    notAfter,
  });
  const leafDer = await certificate({
    subject: "Test App Store Signing",
    issuer: "Test WWDR",
    serial: 3,
    publicKey: leaf.publicKey,
    signingKey: intermediate.privateKey,
    hash: "SHA-384",
    extensions: options.leafMarker === false ? [] : [marker(APPLE_LEAF_MARKER_OID)],
    notBefore,
    notAfter,
  });
  return { rootDer, intermediateDer, leafDer, leafKey: leaf.privateKey };
}

/** Signs `payload` as an `ES256` JWS whose `x5c` is `chain` (leaf, intermediate, root). */
export async function signJws(payload: unknown, chain: TestChain, header: Record<string, unknown> = {}): Promise<string> {
  const fullHeader = {
    alg: "ES256",
    x5c: [chain.leafDer, chain.intermediateDer, chain.rootDer].map(base64),
    ...header,
  };
  const signingInput = `${base64Url(new TextEncoder().encode(JSON.stringify(fullHeader)))}.${base64Url(
    new TextEncoder().encode(JSON.stringify(payload)),
  )}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, chain.leafKey, new TextEncoder().encode(signingInput)),
  );
  return `${signingInput}.${base64Url(signature)}`;
}

/** A JWS whose signature is not checked: the shape a StoreKit test transaction in Xcode takes. */
export function unsignedJws(payload: unknown): string {
  const header = base64Url(new TextEncoder().encode(JSON.stringify({ alg: "ES256", x5c: ["AA=="] })));
  return `${header}.${base64Url(new TextEncoder().encode(JSON.stringify(payload)))}.${base64Url(new Uint8Array(64))}`;
}

export function base64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

export function base64Url(bytes: Uint8Array): string {
  return base64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
