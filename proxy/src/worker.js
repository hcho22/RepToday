/**
 * FitSnack Variety Language proxy (US-N05).
 *
 * A thin, stateless key-holding proxy for the deferred Phase 2 Variety Language LLM slice (US-G03).
 * It holds the Anthropic API key (so the key never ships in the app) and makes **exactly one**
 * Claude call per request, turning the engine's genuine day-to-day contrast into one short,
 * plain-language line ("Today leans into mobility - yesterday was strength").
 *
 * Privacy by construction:
 *   - The request carries only two pillar values (today, and yesterday when it differs) plus their
 *     labels - never user identity, profile, `why`, or history. There is nothing sensitive to log.
 *   - Nothing is persisted: no KV, no D1, no cache, no scheduler, no request-body logging. History
 *     is read transiently from the request and discarded when the response is sent.
 *
 * Never a dependency the app waits on: the client enforces its own short timeout and falls back to
 * the deterministic on-device template on any failure, timeout, or absence of this proxy.
 *
 * Wire contract (see ../README.md):
 *   POST /variety-language
 *   Request:  { "today": "<pillar>", "yesterday"?: "<pillar>",
 *               "todayLabel": "<word>", "yesterdayLabel"?: "<word>" }
 *   Response: 200 { "line": "<one short line>" }  |  4xx/5xx { "error": "<code>" }
 */

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
// Default to the most capable model per Anthropic guidance; override with the ANTHROPIC_MODEL var
// (e.g. a Haiku tier) when latency or cost on this felt-nicety path matters more than prose quality.
const DEFAULT_MODEL = "claude-opus-4-8";
// A short single line never needs many tokens.
const MAX_TOKENS = 64;
// Bound the upstream call so a slow Anthropic response can't hold the Worker (and the app) open.
const UPSTREAM_TIMEOUT_MS = 8000;

const VALID_PILLARS = new Set(["strength", "mobility", "primal"]);

const SYSTEM_PROMPT = [
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

export default {
  /**
   * @param {Request} request
   * @param {{ ANTHROPIC_API_KEY?: string, ANTHROPIC_MODEL?: string }} env
   */
  async fetch(request, env) {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }

    let payload;
    try {
      payload = await request.json();
    } catch {
      return json({ error: "invalid_json" }, 400);
    }

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

    const userPrompt = buildPrompt(todayLabel, yesterday === null ? null : yesterdayLabel);

    let upstream;
    try {
      upstream = await fetch(ANTHROPIC_URL, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-api-key": env.ANTHROPIC_API_KEY,
          "anthropic-version": ANTHROPIC_VERSION,
        },
        // Thinking is intentionally omitted: on Opus 4.7/4.8 an omitted `thinking` field runs
        // without extended thinking, which is what this fast, single-line generation wants.
        body: JSON.stringify({
          model: env.ANTHROPIC_MODEL || DEFAULT_MODEL,
          max_tokens: MAX_TOKENS,
          system: SYSTEM_PROMPT,
          messages: [{ role: "user", content: userPrompt }],
        }),
        signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
      });
    } catch {
      // Timeout or network error reaching Anthropic.
      return json({ error: "upstream_unreachable" }, 502);
    }

    if (!upstream.ok) {
      return json({ error: "upstream_error", status: upstream.status }, 502);
    }

    let message;
    try {
      message = await upstream.json();
    } catch {
      return json({ error: "upstream_bad_json" }, 502);
    }

    const line = extractText(message);
    if (!line) {
      return json({ error: "empty_line" }, 502);
    }

    return json({ line }, 200);
  },
};

/** Build the one-shot user prompt from the labels the app already produced. */
function buildPrompt(todayLabel, yesterdayLabel) {
  if (yesterdayLabel) {
    return `Today's focus: ${todayLabel}. Previous session's focus: ${yesterdayLabel}. Write the line.`;
  }
  return `Today's focus: ${todayLabel}. There is no previous session to contrast. Write the line.`;
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

/** JSON response helper. */
function json(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
