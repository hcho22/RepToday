const GUARD_STAGES = ['worker_envelope', 'worker_state', 'do_preflight', 'do_token_entry', 'do_token_transaction', 'do_state'];
const GUARD_REASONS = ['envelope', 'key_format', 'prefix_format', 'token_syntax', 'token_mac', 'token_claims', 'token_future', 'token_expired', 'denied'];
const TOKEN = ['token_syntax', 'token_mac', 'token_claims', 'token_future', 'token_expired'];
const FINAL = {
  worker_envelope: ['missing_proof', 'proof_envelope', 'enrollment_envelope', 'delete_envelope',
    'attestation_encoding', 'assertion_encoding'],
  worker_token: TOKEN,
  worker_state: ['denied', 'not_authorized'],
  worker_operator: ['authorization', 'request_shape'],
  worker_handler: ['authorization'],
  worker_premium: ['denied', 'presented_environment', 'presented_chain', 'status_identity',
    'status_count', 'status_match', 'premium_policy'],
  do_preflight: ['key_format', 'prefix_format', 'request_shape', 'attestation_encoding', 'assertion_encoding'],
  do_token_entry: TOKEN,
  do_token_transaction: TOKEN,
  do_state: ['denied', 'pending_challenge', 'enrollment_conflict'],
  do_attestation: ['attestation_cbor', 'attestation_shape', 'attestation_certificate', 'attestation_chain',
    'attestation_result', 'attestation_identity'],
  do_assertion: ['assertion_cbor', 'assertion_shape', 'assertion_counter', 'assertion_signature', 'assertion_result'],
};

// Temporary opt-in diagnostics; no identifiers or arbitrary exception data accepted.
export function emitAuthGuardDiagnostic(env, stage, reason, deltaMs = undefined) {
  if (env.COACH_AUTH_GUARD_DIAGNOSTICS !== '1') return;
  if (!GUARD_STAGES.includes(stage) || !GUARD_REASONS.includes(reason)) return;
  const includeDelta = ['token_future', 'token_expired'].includes(reason) && Number.isInteger(deltaMs) && Math.abs(deltaMs) <= 60_000;
  const row = { event: 'coach_auth_guard', stage, reason, ...(includeDelta ? { deltaMs } : {}) };
  try { console.log(JSON.stringify(row)); } catch {} // Never alter the public result.
}

// Separate, default-off opt-in. Only final admission failures; no
// identifiers, lengths, timestamps, deltas, values, or arbitrary exception text.
export function emitFinalAuthDiagnostic(env, stage, reason) {
  if (env.COACH_FINAL_AUTH_DIAGNOSTICS !== '1') return;
  if (!Object.hasOwn(FINAL, stage) || !FINAL[stage].includes(reason)) return;
  try { console.log(JSON.stringify({ event: 'coach_final_auth_guard', stage, reason })); } catch {}
}

// Staging-only response label: one known `<stage>/<reason>` pair from the vocabularies above, else null.
// Only a separate staging Worker sets COACH_STAGING_LABELS; the production verifier rejects that binding.
export const stagingLabelsEnabled = env => env?.COACH_STAGING_LABELS === '1';
export function diagnosticLabel(stage, reason) {
  if (typeof stage !== 'string' || typeof reason !== 'string') return null;
  const known = Object.hasOwn(FINAL, stage) && FINAL[stage].includes(reason) ||
    GUARD_STAGES.includes(stage) && GUARD_REASONS.includes(reason);
  return known ? `${stage}/${reason}` : null;
}
export function parseDiagnosticLabel(label) {
  if (typeof label !== 'string' || label.length > 64) return null;
  const parts = label.split('/');
  return parts.length === 2 ? diagnosticLabel(parts[0], parts[1]) : null;
}
export function allDiagnosticLabels() {
  const labels = Object.entries(FINAL).flatMap(([stage, reasons]) => reasons.map(reason => `${stage}/${reason}`));
  for (const stage of GUARD_STAGES) for (const reason of GUARD_REASONS) labels.push(`${stage}/${reason}`);
  return [...new Set(labels.filter(label => parseDiagnosticLabel(label) === label))].sort();
}

// Staging only: non-secret digest prefixes of what the server verified an assertion against, so a
// device's signed values can be compared offline. Anything outside this exact shape is dropped.
const ASSERTION_DIGEST = /^payload=[0-9a-f]{16} body=[0-9a-f]{16} transaction=[0-9a-f]{16} challenge=[A-Za-z0-9_-]{8}$/;
export const parseAssertionDigest = value => typeof value === 'string' && ASSERTION_DIGEST.test(value) ? value : null;
