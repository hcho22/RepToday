/**
 * Rep Today LLM proxy.
 *
 * A thin, stateless, key-holding proxy for Rep Today's Phase 2 LLM slices. It holds upstream API
 * keys (so they never ship in the app) and makes **exactly one** model call per request. Two
 * routes live here, and both are stateless and store nothing:
 *
 *   POST /variety-language  (US-N05) - turns the engine's genuine day-to-day contrast into one short
 *                           plain-language line ("Today leans into mobility - yesterday was strength").
 *   POST /coach             (US-AC01) - the premium AI coach transport: a derived, non-identifying
 *                           context bundle + the user's message + a Coach-only pseudonym in; an
 *                           OpenAI reply or provider-independent safety outcome out.
 *
 * Privacy by construction (both routes):
 *   - The request carries no Rep Today identity: no account, `installId`, IDFA, Apple ID, email,
 *     name, or profile. `/variety-language` carries only two pillar values; `/coach` carries the
 *     app-audited `CoachContextBundle`, the free-text the user typed, and a separately generated
 *     random pseudonym used only as OpenAI's abuse-prevention `safety_identifier`.
 *   - Nothing is persisted: no KV, no D1, no cache, no scheduler, and **no request/response body
 *     logging**. History is read transiently from the request and discarded when the response is
 *     sent. Conversation memory, if any, lives on the device in the client - never here.
 *
 * Never a dependency the app waits on: each client enforces its own short timeout and degrades
 * cleanly (Variety Language falls back to the on-device template; the coach surface shows a
 * non-blocking error) on any failure, timeout, or absence of this proxy.
 *
 * Wire contracts: see ../README.md.
 */

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
// Default to the most capable model per Anthropic guidance; override with the ANTHROPIC_MODEL var
// (e.g. a Haiku tier) when latency or cost matters more than prose quality.
const DEFAULT_MODEL = "claude-opus-4-8";

const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";
// The Coach model is intentionally route-specific. Variety Language remains on its independent
// Claude configuration and cannot be moved by a Coach model change.
const COACH_MODEL = "gpt-5.6-luna";

// --- Variety Language route tuning ---
// A short single line never needs many tokens.
const VARIETY_MAX_TOKENS = 64;
// Bound the upstream call so a slow Anthropic response can't hold the Worker (and the app) open.
const VARIETY_UPSTREAM_TIMEOUT_MS = 8000;

// --- Coach route tuning ---
// A coach answer is a few sentences of guidance, not a one-liner.
const COACH_MAX_TOKENS = 1024;
// Longer than the Variety Language line but still firmly bounded so the coach surface never hangs.
const COACH_UPSTREAM_TIMEOUT_MS = 30000;
// A coach question is a sentence or two; cap the free-text so one turn stays small and cheap. The iOS
// client caps the same value, so this is defense in depth, not the only gate.
const COACH_MAX_MESSAGE_CHARS = 2000;
const COACH_SAFETY_REFUSAL_OUTCOME = "safety_refusal";
const COACH_SAFETY_IDENTIFIER_PATTERN =
  /^coach-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// The maximum request body accepted on any route, checked BEFORE parsing so an oversized payload can
// never reach JSON parsing (or bill a model call). The coach bundle + a capped message is small;
// this leaves generous headroom while refusing anything abusive.
const MAX_BODY_BYTES = 32 * 1024;

const VALID_PILLARS = new Set(["strength", "mobility", "primal"]);

const VARIETY_SYSTEM_PROMPT = [
  "You write one short, plain-language line for a micro-workout app that names what today's session",
  "focuses on and, when it differs, contrasts it with the previous session.",
  "Rules you must follow exactly:",
  "1. Name today's focus using the given label.",
  "2. Mention the previous session ONLY if a yesterday label is provided; never invent one.",
  "3. Do not claim a contrast that was not given - if no yesterday label is provided, only name today.",
  "4. Keep it to at most 12 words, warm and matter-of-fact. No emoji, no hype, no exclamation marks.",
  "5. Do not reference the user, their goals, streaks, or any personal detail - you have none.",
  "6. Reply with the line only - no quotes, no preamble, no explanation.",
].join(" ");

// The coach persona (US-AC02, the talking coach). It refines US-AC01's minimal transport-only stub
// with the target intents, the app's voice, and the safety framing. The load-bearing invariant is
// unchanged and stated first so it can never be crowded out: the coach only ever *talks* - it never
// generates, edits, or prescribes a workout (the deterministic on-device engine owns every session
// and all safety), and it grounds itself in the provided context, never inventing history it was not
// given. It explains the engine's real reasoning (stalest-pattern focus, progression frontier,
// forgiving consistency) rather than substituting its own programming.
const COACH_SYSTEM_PROMPT = [
  "You are the coach inside Rep Today, a discipline-first micro-workout app for busy, desk-bound",
  "adults. Every session is built by a deterministic on-device engine that you do NOT control and",
  "cannot change: it picks movements by the user's stalest movement pattern, advances them one tier",
  "along a progression chain only when they clear the criteria, keeps every session strength-led with",
  "mobility as the warm-up and cooldown, and fits the whole thing to the minutes the user asked for.",
  "Strength is earned, not chosen: harder skills unlock through sustained consistency and demonstrated",
  "competence (the earned Strength Phase), never on request.",
  "You are given a small, non-identifying summary of the user's progress - their phase, per-pattern",
  "chain positions (current movement, tier, whether a harder tier exists), the patterns they trained",
  "recently, a coarse consistency signal, a per-pattern strength-journey trend (each foundational",
  "pattern marked climbing, flat, or steady, with how many weeks it has sat at its current tier), and",
  "the minutes they requested - plus their message. That summary is everything you know about them.",
  "Rules you must follow exactly:",
  "1. You NEVER generate, edit, prescribe, swap, add, remove, or reorder a workout, exercise, set, rep,",
  "   or duration, and you never tell the user you have changed their session. The engine owns every",
  "   session and all safety. You may only explain the engine's choices, teach movement form, and",
  "   encourage - talking only. If asked to change the workout, say the engine handles that and explain",
  "   why it chose what it did.",
  "2. Ground every answer in the provided context; never invent history, numbers, streaks, or identity",
  "   you were not given. If the context does not say, tell the user you can only speak to what you can",
  "   see. Do not claim to have adjusted anything.",
  "3. Answer the user's real intent. Common questions and how to handle them:",
  "   - 'Why this workout / why this movement today?': explain the engine's reasoning from the context",
  "     - the stalest-pattern focus, their current chain tier, the requested length - never a made-up",
  "     reason.",
  "   - 'How do I do <movement>?': give correct, safe, concise form cues for that bodyweight movement",
  "     (setup, the key positions, one or two common faults to avoid). No equipment - everything is",
  "     zero-equipment bodyweight.",
  "   - 'Is <movement> safe with <pain/complaint>?' or any mention of pain or injury: give general,",
  "     non-diagnostic safety guidance, suggest an easier variation or stopping if it hurts, and invite",
  "     them to flag that area themselves in the app's injury settings so future sessions work around",
  "     it. You cannot set, clear, or read that flag - only the user can, and only in that screen. Never",
  "     say or imply that you have flagged it, removed a movement, or changed anything; say what they",
  "     can do, in the future tense. Never diagnose, never prescribe medical treatment.",
  "   - 'I'm bored / this feels repetitive': explain that variety is built in - the engine rotates",
  "     movement patterns and avoids repeating recent ones, and new tiers unlock as they progress -",
  "     and reassure them the sameness is the discipline working, not a rut.",
  "   - 'How am I doing / how's my progress?': narrate a concrete, specific insight from the",
  "     strength-journey trend in the context - name what is climbing and what has gone flat and for",
  "     how long ('your push is climbing, your hinge has been flat about 3 weeks') rather than a",
  "     generic summary. If a pattern has stalled you may suggest leaning the program toward it for a",
  "     while, framed as a preference the app will apply - never say you have already changed anything,",
  "     and never edit the workout yourself; the app owns every session.",
  "4. Voice: warm, specific, and concise (a few sentences, not an essay). Identity-framed - 'you're",
  "   someone who shows up', 'this is you building the habit' - and NEVER shaming, loss-framed, or",
  "   gamified. No streaks-to-break, no points, no levels, no guilt about missed days.",
].join(" ");

export default {
  /**
   * @param {Request} request
   * @param {{ ANTHROPIC_API_KEY?: string, ANTHROPIC_MODEL?: string, OPENAI_API_KEY?: string, CLIENT_SHARED_SECRET?: string }} env
   */
  async fetch(request, env) {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }

    // Abuse gate: when a client shared secret is configured, reject any request whose
    // `Authorization: Bearer <secret>` header does not match BEFORE calling a billed provider, so
    // an unauthorized caller can never drive a paid model call. Left open only when the secret is
    // unset (local dev); production deploys MUST set it (see ../README.md, "Abuse protection").
    if (env.CLIENT_SHARED_SECRET && !isAuthorized(request, env.CLIENT_SHARED_SECRET)) {
      return json({ error: "unauthorized" }, 401);
    }

    // Route by path. `/coach` is the premium coach transport; everything else is the Variety Language
    // route (the client posts to `/variety-language`), whose behavior is unchanged.
    const path = new URL(request.url).pathname;
    if (path === "/coach" || path.endsWith("/coach")) {
      return handleCoach(request, env);
    }
    return handleVarietyLanguage(request, env);
  },
};

// MARK: - Variety Language route (US-N05)

async function handleVarietyLanguage(request, env) {
  const parsed = await parseCappedJson(request, MAX_BODY_BYTES);
  if (parsed.tooLarge) {
    return json({ error: "payload_too_large" }, 413);
  }
  if (parsed.invalid) {
    return json({ error: "invalid_json" }, 400);
  }
  const payload = parsed.value;

  const today = payload?.today;
  const yesterday = payload?.yesterday ?? null;
  const todayLabel = typeof payload?.todayLabel === "string" ? payload.todayLabel : today;
  const yesterdayLabel =
    typeof payload?.yesterdayLabel === "string" ? payload.yesterdayLabel : yesterday;

  if (!VALID_PILLARS.has(today)) {
    return json({ error: "invalid_today" }, 400);
  }
  if (yesterday !== null && !VALID_PILLARS.has(yesterday)) {
    return json({ error: "invalid_yesterday" }, 400);
  }
  if (!env.ANTHROPIC_API_KEY) {
    // Misconfiguration, not a client error - but never leak details.
    return json({ error: "not_configured" }, 500);
  }

  const userPrompt = buildVarietyPrompt(todayLabel, yesterday === null ? null : yesterdayLabel);

  const message = await callClaude(env, {
    system: VARIETY_SYSTEM_PROMPT,
    userPrompt,
    maxTokens: VARIETY_MAX_TOKENS,
    timeoutMs: VARIETY_UPSTREAM_TIMEOUT_MS,
  });
  if (message.error) {
    return json({ error: message.error, ...(message.status ? { status: message.status } : {}) }, 502);
  }

  const line = extractText(message.body);
  if (!line) {
    return json({ error: "empty_line" }, 502);
  }
  return json({ line }, 200);
}

// MARK: - Coach route (US-AC01)

async function handleCoach(request, env) {
  const parsed = await parseCappedJson(request, MAX_BODY_BYTES);
  if (parsed.tooLarge) {
    return json({ error: "payload_too_large" }, 413);
  }
  if (parsed.invalid) {
    return json({ error: "invalid_json" }, 400);
  }
  const payload = parsed.value;

  // Validate the request shape BEFORE any upstream call so a malformed or oversized turn never bills
  // a model call. The context bundle is app-authored; validate it is present and object-shaped
  // (not a deep schema check - the app owns the audited `CoachContextBundle` definition).
  const context = payload?.context;
  if (typeof context !== "object" || context === null || Array.isArray(context)) {
    return json({ error: "invalid_context" }, 400);
  }
  const message = payload?.message;
  if (typeof message !== "string" || message.trim().length === 0) {
    return json({ error: "invalid_message" }, 400);
  }
  if (message.length > COACH_MAX_MESSAGE_CHARS) {
    return json({ error: "message_too_long" }, 413);
  }
  const safetyIdentifier = payload?.safetyIdentifier;
  if (
    typeof safetyIdentifier !== "string" ||
    !COACH_SAFETY_IDENTIFIER_PATTERN.test(safetyIdentifier)
  ) {
    return json({ error: "invalid_safety_identifier" }, 400);
  }
  if (!env.OPENAI_API_KEY) {
    return json({ error: "not_configured" }, 500);
  }

  const userPrompt = buildCoachPrompt(context, message.trim());

  const upstream = await callCoachModel(env, {
    system: COACH_SYSTEM_PROMPT,
    userPrompt,
    safetyIdentifier,
    maxTokens: COACH_MAX_TOKENS,
    timeoutMs: COACH_UPSTREAM_TIMEOUT_MS,
  });
  if (upstream.error) {
    return json({ error: upstream.error, ...(upstream.status ? { status: upstream.status } : {}) }, 502);
  }

  const outcome = extractOpenAIOutcome(upstream.body);
  if (outcome.kind === "error") {
    return json({ error: "upstream_error" }, 502);
  }
  if (outcome.kind === "refusal") {
    return json({ outcome: COACH_SAFETY_REFUSAL_OUTCOME }, 200);
  }
  if (outcome.kind === "empty") {
    return json({ error: "empty_reply" }, 502);
  }
  return json({ reply: outcome.reply }, 200);
}

// MARK: - Shared machinery

/**
 * Read the request body with a hard byte cap, then JSON-parse it. Returns one of:
 *   { tooLarge: true }              - body exceeded `maxBytes` (checked before parsing)
 *   { invalid: true }               - body was not valid JSON
 *   { value: <parsed> }             - success
 *
 * The body is buffered once here and never logged or persisted.
 */
async function parseCappedJson(request, maxBytes) {
  // Fast reject on a declared oversize before buffering anything.
  const declared = Number(request.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > maxBytes) {
    return { tooLarge: true };
  }
  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > maxBytes) {
    return { tooLarge: true };
  }
  try {
    return { value: JSON.parse(raw) };
  } catch {
    return { invalid: true };
  }
}

/**
 * Make the Variety Language route's single bounded Claude call. Returns `{ body }` on success or
 * `{ error, status? }` on any misconfiguration/upstream failure (the caller maps these to a 502/500).
 * Extended thinking is intentionally not requested (fast generation on both routes).
 *
 * @param {{ ANTHROPIC_API_KEY?: string, ANTHROPIC_MODEL?: string }} env
 * @param {{ system: string, userPrompt: string, maxTokens: number, timeoutMs: number }} opts
 */
async function callClaude(env, opts) {
  let upstream;
  try {
    upstream = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      body: JSON.stringify({
        model: env.ANTHROPIC_MODEL || DEFAULT_MODEL,
        max_tokens: opts.maxTokens,
        system: opts.system,
        messages: [{ role: "user", content: opts.userPrompt }],
      }),
      signal: AbortSignal.timeout(opts.timeoutMs),
    });
  } catch {
    // Timeout or network error reaching Anthropic.
    return { error: "upstream_unreachable" };
  }

  if (!upstream.ok) {
    return { error: "upstream_error", status: upstream.status };
  }

  try {
    return { body: await upstream.json() };
  } catch {
    return { error: "upstream_bad_json" };
  }
}

/**
 * Make the Coach's single bounded OpenAI Responses API call. The request is stateless (`store:
 * false`) and uses no tools. `reasoning.effort: "none"` preserves the previous no-extended-thinking
 * latency posture, while `max_output_tokens` preserves the existing output ceiling. The dedicated
 * app pseudonym is forwarded as `safety_identifier`, never included in the model prompt.
 *
 * @param {{ OPENAI_API_KEY?: string }} env
 * @param {{ system: string, userPrompt: string, safetyIdentifier: string, maxTokens: number, timeoutMs: number }} opts
 */
async function callCoachModel(env, opts) {
  let upstream;
  try {
    upstream = await fetch(OPENAI_RESPONSES_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${env.OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: COACH_MODEL,
        instructions: opts.system,
        input: opts.userPrompt,
        max_output_tokens: opts.maxTokens,
        reasoning: { effort: "none" },
        store: false,
        safety_identifier: opts.safetyIdentifier,
      }),
      signal: AbortSignal.timeout(opts.timeoutMs),
    });
  } catch {
    return { error: "upstream_unreachable" };
  }

  if (!upstream.ok) {
    return { error: "upstream_error", status: upstream.status };
  }

  try {
    return { body: await upstream.json() };
  } catch {
    return { error: "upstream_bad_json" };
  }
}

/**
 * Whether the request carries the expected `Authorization: Bearer <secret>` header, compared in
 * constant time so the check never leaks the secret's length or contents through timing.
 */
function isAuthorized(request, expectedSecret) {
  const header = request.headers.get("authorization") || "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    return false;
  }
  return constantTimeEquals(match[1], expectedSecret);
}

/** Length-independent constant-time string comparison. */
function constantTimeEquals(a, b) {
  const aBytes = new TextEncoder().encode(a);
  const bBytes = new TextEncoder().encode(b);
  // Fold the length difference into the accumulator so mismatched lengths still run to completion.
  let diff = aBytes.length ^ bBytes.length;
  const max = Math.max(aBytes.length, bBytes.length);
  for (let i = 0; i < max; i++) {
    diff |= (aBytes[i] ?? 0) ^ (bBytes[i] ?? 0);
  }
  return diff === 0;
}

/** Build the one-shot Variety Language prompt from the labels the app already produced. */
function buildVarietyPrompt(todayLabel, yesterdayLabel) {
  if (yesterdayLabel) {
    return `Today's focus: ${todayLabel}. Previous session's focus: ${yesterdayLabel}. Write the line.`;
  }
  return `Today's focus: ${todayLabel}. There is no previous session to contrast. Write the line.`;
}

/**
 * Build the coach user prompt: the derived context as compact JSON plus the user's question. The
 * context is serialized as-is (it is the app's audited, non-identifying bundle) so the model sees the
 * same summary the app defined, and nothing more.
 */
function buildCoachPrompt(context, message) {
  return [
    "User's progress context (a non-identifying summary):",
    JSON.stringify(context),
    "",
    "User's message:",
    message,
  ].join("\n");
}

/** Join and trim the text blocks of an Anthropic Messages response. */
function extractText(message) {
  const blocks = Array.isArray(message?.content) ? message.content : [];
  return blocks
    .filter((block) => block?.type === "text" && typeof block.text === "string")
    .map((block) => block.text)
    .join("")
    .trim();
}

/**
 * @returns {{ kind: "error" } | { kind: "refusal" } | { kind: "reply", reply: string } | { kind: "empty" }}
 */
function extractOpenAIOutcome(response) {
  if (response?.error != null) {
    return { kind: "error" };
  }

  switch (response?.status) {
    case "completed":
      if (response?.incomplete_details?.reason === "content_filter") {
        return { kind: "refusal" };
      }
      break;
    case "incomplete":
      if (response?.incomplete_details?.reason === "content_filter") {
        return { kind: "refusal" };
      }
      if (response?.incomplete_details?.reason !== "max_output_tokens") {
        return { kind: "error" };
      }
      break;
    case "failed":
    case "cancelled":
    case "queued":
    case "in_progress":
    default:
      return { kind: "error" };
  }

  const output = Array.isArray(response?.output) ? response.output : [];
  const blocks = output.flatMap((item) => (Array.isArray(item?.content) ? item.content : []));
  if (blocks.some((block) => block?.type === "refusal")) {
    return { kind: "refusal" };
  }
  const reply = blocks
    .filter((block) => block?.type === "output_text" && typeof block.text === "string")
    .map((block) => block.text)
    .join("")
    .trim();
  return reply ? { kind: "reply", reply } : { kind: "empty" };
}

/** JSON response helper. */
function json(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
