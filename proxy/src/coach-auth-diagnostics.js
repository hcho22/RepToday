// Temporary opt-in diagnostics; no identifiers or arbitrary exception data accepted.
export function emitAuthGuardDiagnostic(env, stage, reason, deltaMs = undefined) {
  if (env.COACH_AUTH_GUARD_DIAGNOSTICS !== '1') return;
  const stages = ['worker_envelope', 'worker_state', 'do_preflight', 'do_token_entry', 'do_token_transaction', 'do_state'];
  const reasons = ['envelope', 'key_format', 'prefix_format', 'token_syntax', 'token_mac', 'token_claims', 'token_future', 'token_expired', 'denied'];
  if (!stages.includes(stage) || !reasons.includes(reason)) return;
  const includeDelta = ['token_future', 'token_expired'].includes(reason) && Number.isInteger(deltaMs) && Math.abs(deltaMs) <= 60_000;
  const row = { event: 'coach_auth_guard', stage, reason, ...(includeDelta ? { deltaMs } : {}) };
  try { console.log(JSON.stringify(row)); } catch {} // Never alter the public result.
}
