import * as asn1js from "asn1js";
import * as pkijs from "pkijs";

/**
 * Verification of Apple's signed App Store data (M4, US-CA02, ADR-0017): the JWS strings App Store
 * Server Notifications V2 carry (`signedPayload`, `signedTransactionInfo`, `signedRenewalInfo`) and the
 * `jwsRepresentation` of a StoreKit 2 transaction the app sends when it links a purchase.
 *
 * It does what Apple's own `SignedDataVerifier` does with online checks off, on WebCrypto so it runs
 * in Convex's default runtime:
 *
 * 1. The header is `ES256` and carries a three-certificate `x5c` chain: leaf, intermediate, root.
 * 2. The root is byte-for-byte one of the pinned trust anchors (Apple Root CA - G3 and G2 in
 *    production, `convex/appleRoots.ts`); a chain ending anywhere else is refused.
 * 3. The intermediate is signed by the root and the leaf by the intermediate.
 * 4. The intermediate carries Apple's WWDR intermediate marker extension and the leaf Apple's App
 *    Store receipt-signing marker, so a certificate Apple issued for something else cannot sign.
 * 5. Every certificate is valid at the payload's own `signedDate` (or now, when it has none).
 * 6. The JWS signature verifies with the leaf's P-256 key.
 *
 * Only then is the payload returned. Every failure is the one `AppStoreVerificationError`, whose
 * `reason` is a fixed label that never echoes the payload.
 */

/** OID Apple sets on the App Store receipt-signing leaf certificate. */
export const APPLE_LEAF_MARKER_OID = "1.2.840.113635.100.6.11.1";
/** OID Apple sets on the Worldwide Developer Relations intermediate certificate. */
export const APPLE_INTERMEDIATE_MARKER_OID = "1.2.840.113635.100.6.2.1";
/** The P-256 named-curve OID the leaf key must use for `ES256`. */
const P256_OID = "1.2.840.10045.3.1.7";
/** The longest JWS accepted; a real notification or transaction is a few kilobytes. */
export const MAX_JWS_LENGTH = 32 * 1024;

export type AppStoreVerificationReason =
  | "malformed"
  | "algorithm"
  | "chain_shape"
  | "untrusted_root"
  | "chain_signature"
  | "marker_extension"
  | "certificate_validity"
  | "leaf_key"
  | "signature";

export class AppStoreVerificationError extends Error {
  constructor(readonly reason: AppStoreVerificationReason) {
    super(`App Store signed data failed verification: ${reason}`);
  }
}

export type VerifyOptions = {
  /** DER bytes of every trusted root. */
  trustedRoots: Uint8Array[];
  /** The clock used when the payload carries no `signedDate`. */
  now?: () => number;
};

/** Verifies `jws` against the pinned roots and returns its decoded payload. */
export async function verifyAppleSignedData(jws: string, options: VerifyOptions): Promise<Record<string, unknown>> {
  const parts = splitJws(jws);
  const header = parseJsonSegment(parts[0]);
  const payload = parseJsonSegment(parts[1]);
  if (header.alg !== "ES256") {
    throw new AppStoreVerificationError("algorithm");
  }
  const x5c = header.x5c;
  if (!Array.isArray(x5c) || x5c.length !== 3 || x5c.some((entry) => typeof entry !== "string" || entry.length > 8192)) {
    throw new AppStoreVerificationError("chain_shape");
  }
  const ders = x5c.map((entry) => decodeBase64(entry as string, "chain_shape"));
  const [leaf, intermediate, root] = ders.map(parseCertificate);

  if (!options.trustedRoots.some((trusted) => bytesEqual(trusted, ders[2]))) {
    throw new AppStoreVerificationError("untrusted_root");
  }
  if (!(await verifiesWith(intermediate, root)) || !(await verifiesWith(leaf, intermediate))) {
    throw new AppStoreVerificationError("chain_signature");
  }
  if (!hasExtension(intermediate, APPLE_INTERMEDIATE_MARKER_OID) || !hasExtension(leaf, APPLE_LEAF_MARKER_OID)) {
    throw new AppStoreVerificationError("marker_extension");
  }
  const signedDate = typeof payload.signedDate === "number" && Number.isFinite(payload.signedDate) ? payload.signedDate : undefined;
  const effective = signedDate ?? (options.now ?? Date.now)();
  for (const certificate of [leaf, intermediate, root]) {
    if (effective < certificate.notBefore.value.getTime() || effective > certificate.notAfter.value.getTime()) {
      throw new AppStoreVerificationError("certificate_validity");
    }
  }

  const key = await leafKey(leaf);
  const signature = decodeBase64Url(parts[2], "signature");
  if (signature.length !== 64) {
    throw new AppStoreVerificationError("signature");
  }
  const signed = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const valid = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, toArrayBuffer(signature), signed);
  if (!valid) {
    throw new AppStoreVerificationError("signature");
  }
  return payload;
}

/**
 * Decodes a JWS payload **without** verifying it. Used only to read the `environment` an unverified
 * StoreKit test transaction claims, so the dev-only Xcode path (`APPSTORE_ALLOW_XCODE`) can accept
 * exactly the payloads Apple's own library accepts unverified, and nothing else.
 */
export function decodeUnverifiedPayload(jws: string): Record<string, unknown> {
  const parts = splitJws(jws);
  return parseJsonSegment(parts[1]);
}

// MARK: - Helpers

function splitJws(jws: string): [string, string, string] {
  if (typeof jws !== "string" || jws.length === 0 || jws.length > MAX_JWS_LENGTH) {
    throw new AppStoreVerificationError("malformed");
  }
  const parts = jws.split(".");
  if (parts.length !== 3 || parts.some((part) => part.length === 0 || !/^[A-Za-z0-9_-]+$/.test(part))) {
    throw new AppStoreVerificationError("malformed");
  }
  return [parts[0], parts[1], parts[2]];
}

function parseJsonSegment(segment: string): Record<string, unknown> {
  try {
    const value: unknown = JSON.parse(new TextDecoder().decode(decodeBase64Url(segment, "malformed")));
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
      throw new AppStoreVerificationError("malformed");
    }
    return value as Record<string, unknown>;
  } catch (error) {
    if (error instanceof AppStoreVerificationError) throw error;
    throw new AppStoreVerificationError("malformed");
  }
}

function parseCertificate(der: Uint8Array): pkijs.Certificate {
  try {
    const parsed = asn1js.fromBER(toArrayBuffer(der));
    if (parsed.offset === -1 || parsed.offset !== der.length) {
      throw new AppStoreVerificationError("chain_shape");
    }
    return new pkijs.Certificate({ schema: parsed.result });
  } catch (error) {
    if (error instanceof AppStoreVerificationError) throw error;
    throw new AppStoreVerificationError("chain_shape");
  }
}

async function verifiesWith(certificate: pkijs.Certificate, issuer: pkijs.Certificate): Promise<boolean> {
  try {
    return await certificate.verify(issuer);
  } catch {
    return false;
  }
}

function hasExtension(certificate: pkijs.Certificate, oid: string): boolean {
  return (certificate.extensions ?? []).some((extension) => extension.extnID === oid);
}

async function leafKey(leaf: pkijs.Certificate): Promise<CryptoKey> {
  const info = leaf.subjectPublicKeyInfo;
  const curve = info.algorithm.algorithmParams;
  const curveOid = curve instanceof asn1js.ObjectIdentifier ? curve.valueBlock.toString() : undefined;
  if (info.algorithm.algorithmId !== "1.2.840.10045.2.1" || curveOid !== P256_OID) {
    throw new AppStoreVerificationError("leaf_key");
  }
  try {
    const spki = info.toSchema().toBER(false);
    return await crypto.subtle.importKey("spki", spki, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
  } catch {
    throw new AppStoreVerificationError("leaf_key");
  }
}

function decodeBase64Url(value: string, reason: AppStoreVerificationReason): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  return decodeBase64(padded, reason);
}

function decodeBase64(value: string, reason: AppStoreVerificationReason): Uint8Array {
  try {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index++) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  } catch {
    throw new AppStoreVerificationError(reason);
  }
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let index = 0; index < a.length; index++) {
    diff |= a[index] ^ b[index];
  }
  return diff === 0;
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}

/** Decodes a base64 trust anchor to DER bytes. */
export function derFromBase64(value: string): Uint8Array {
  return decodeBase64(value, "untrusted_root");
}
