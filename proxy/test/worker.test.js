import { readFileSync, readdirSync } from "node:fs";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/worker.js";

/**
 * Boundary tests for the stateless LLM proxy (US-AC01, plus a Variety Language regression).
 *
 * A single upstream model call is the only network egress each request makes, so stubbing
 * `globalThis.fetch` lets each test assert exactly what the privacy contract requires:
 *   - a valid request returns a reply and makes **exactly one** upstream call;
 *   - an oversized / invalid / unauthorized request is rejected **before** any upstream call;
 *   - nothing is logged (no request/response bodies) and nothing is persisted.
 */

const COACH_URL = "https://proxy.example.com/coach";
const VARIETY_URL = "https://proxy.example.com/variety-language";
const COACH_SAFETY_IDENTIFIER = "coach-00000000-0000-4000-8000-000000000001";

/** A well-formed, non-identifying context bundle (mirrors the iOS `CoachContextBundle`). */
const CONTEXT = {
  phase: "discipline",
  requestedMinutes: 15,
  chainPositions: [
    { pattern: "push", currentExercise: "Standard Push-Up", tier: 3, chainLength: 7, hasNextTier: true },
    { pattern: "pull", currentExercise: "Wall Scapular Pull", tier: 1, chainLength: 3, hasNextTier: true },
    { pattern: "squat", currentExercise: "Bodyweight Squat", tier: 2, chainLength: 6, hasNextTier: true },
    { pattern: "hinge", currentExercise: "Glute Bridge", tier: 1, chainLength: 5, hasNextTier: true },
    { pattern: "core", currentExercise: "Dead Bug", tier: 2, chainLength: 5, hasNextTier: true },
  ],
  recentPatterns: ["push", "core", "squat"],
  consistency: { currentScore: 72, direction: "rising" },
  strengthJourney: [
    { pattern: "hinge", trend: "flat", weeksAtCurrentTier: 3, hasAdvanced: true },
  ],
};

/**
 * The words that must not be in what the Coach model is given or told to say. One list, shared with
 * the app's `CoachRequestVocabularyTests`, which holds the app's side to it.
 */
const INTERNAL_WORDS = JSON.parse(
  readFileSync(new URL("../coach-internal-words.json", import.meta.url), "utf8"),
).words;

/**
 * The requests the app really builds, written by `CoachRequestVocabularyTests` through the app's own
 * send path and pinned there, so these tests check the Worker against what the app sends rather than
 * against a hand-copied shape.
 */
const APP_REQUESTS_URL = new URL("./fixtures/coach-requests/", import.meta.url);
const APP_REQUESTS = readdirSync(APP_REQUESTS_URL)
  .filter((file) => file.endsWith(".json"))
  .sort()
  .map((file) => ({ file, body: JSON.parse(readFileSync(new URL(file, APP_REQUESTS_URL), "utf8")) }));

/**
 * `text` as lowercased whole words, splitting camelCase and punctuation, so "chainPositions" is
 * "chain", "positions" and "discipline" stays one word. The app's suite splits the same way.
 */
function wordsIn(text) {
  return text
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
}

/** Whether `phrase` occurs in `text` as a run of whole words. */
function saysPhrase(text, phrase) {
  const words = wordsIn(text);
  const run = wordsIn(phrase);
  return words.some((_, start) => run.every((word, offset) => words[start + offset] === word));
}

/** The listed words `text` contains, in any form. */
function listedWordsIn(text) {
  return INTERNAL_WORDS.filter(({ forms }) => forms.some((form) => saysPhrase(text, form))).map(({ word }) => word);
}

/**
 * The Coach instructions as sent, split into the one sentence that names the listed words in order to
 * say what to use instead, and everything else.
 */
function splitInstructions(instructions) {
  const text = instructions.replace(/\s+/g, " ");
  const start = text.indexOf("Never use these words in a reply");
  const end = text.indexOf("Use the words the app shows the user.");
  expect(start).toBeGreaterThan(-1);
  expect(end).toBeGreaterThan(start);
  return { wordsToAvoid: text.slice(start, end), rest: `${text.slice(0, start)}${text.slice(end)}` };
}

/**
 * Each sentence of `text` that uses a listed word, as `word: sentence`. A word with an `onlyWith`
 * sense may appear in a sentence that names that sense ("unlock" beside "Strength Phase").
 */
function listedWordUses(text) {
  return text.split(/(?<=\.)\s+/).flatMap((sentence) =>
    INTERNAL_WORDS.filter(
      ({ forms, onlyWith }) =>
        forms.some((form) => saysPhrase(sentence, form)) && !(onlyWith && saysPhrase(sentence, onlyWith)),
    ).map(({ word }) => `${word}: ${sentence}`),
  );
}

/**
 * Every field name in `node` that is more than one word ("chainPositions", "hasNextTier"). A one-word
 * name ("tier", "phase") is also an ordinary word the summary may use, so only these can show that a
 * name was passed through.
 */
function compoundFieldNamesIn(node) {
  if (Array.isArray(node)) {
    return [...new Set(node.flatMap(compoundFieldNamesIn))];
  }
  if (typeof node !== "object" || node === null) {
    return [];
  }
  return [
    ...new Set(
      Object.entries(node).flatMap(([name, value]) => [
        ...(wordsIn(name).length > 1 ? [name] : []),
        ...compoundFieldNamesIn(value),
      ]),
    ),
  ];
}

/** The summary the Worker handed the model: the prompt up to the user's own message. */
function summaryOf(upstreamBody) {
  const [summary] = upstreamBody.input.split("\n\nUser's message:\n");
  return summary;
}

/** Build a Claude-shaped Messages response body. */
function anthropicReply(text) {
  return {
    ok: true,
    async json() {
      return { content: [{ type: "text", text }] };
    },
  };
}

/** Build an OpenAI Responses API-shaped response body. */
function openAIReply(text) {
  return {
    ok: true,
    async json() {
      return {
        status: "completed",
        error: null,
        output: [{ type: "message", content: [{ type: "output_text", text }] }],
      };
    },
  };
}

function openAIRefusal(refusal, text) {
  const content = [
    ...(text ? [{ type: "output_text", text }] : []),
    { type: "refusal", refusal },
  ];
  return {
    ok: true,
    async json() {
      return { status: "completed", error: null, output: [{ type: "message", content }] };
    },
  };
}

/** A stub that stands in for `globalThis.fetch` and records every call. */
let fetchSpy;
let consoleLogSpy;
let consoleErrorSpy;
let consoleWarnSpy;

beforeEach(() => {
  fetchSpy = vi.fn(async () => openAIReply("Because squats are the area you've gone longest without."));
  vi.stubGlobal("fetch", fetchSpy);
  // Prove "no request/response body logging": the Worker must never touch the console.
  consoleLogSpy = vi.spyOn(console, "log").mockImplementation(() => {});
  consoleErrorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
  consoleWarnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

/**
 * @param {object|string} body
 * @param {{ headers?: Record<string, string>, includeSafetyIdentifier?: boolean }} [opts]
 */
function coachRequest(body, { headers, includeSafetyIdentifier = true } = {}) {
  const requestBody =
    includeSafetyIdentifier &&
    typeof body === "object" &&
    body !== null &&
    !Array.isArray(body) &&
    !("safetyIdentifier" in body)
      ? { ...body, safetyIdentifier: COACH_SAFETY_IDENTIFIER }
      : body;
  return new Request(COACH_URL, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: typeof requestBody === "string" ? requestBody : JSON.stringify(requestBody),
  });
}

const ENV = { ANTHROPIC_API_KEY: "sk-ant-test", OPENAI_API_KEY: "sk-openai-test" };

describe("POST /coach", () => {
  it("uses gpt-5.6-luna through the Responses API for a valid Coach request", async () => {
    const response = await worker.fetch(coachRequest({ context: CONTEXT, message: "why squats today?" }), ENV);

    expect(response.status).toBe(200);
    const json = await response.json();
    expect(json).toEqual({ reply: "Because squats are the area you've gone longest without." });

    // Exactly one upstream call, and it is the OpenAI Responses API - no other egress or logging.
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect(fetchSpy.mock.calls[0][0]).toBe("https://api.openai.com/v1/responses");
    const upstreamBody = JSON.parse(fetchSpy.mock.calls[0][1].body);
    expect(upstreamBody.model).toBe("gpt-5.6-luna");
    expect(upstreamBody.reasoning).toEqual({ effort: "none" });
    expect(upstreamBody.max_output_tokens).toBe(1024);
    expect(upstreamBody.store).toBe(false);
    expect(upstreamBody.safety_identifier).toBe(COACH_SAFETY_IDENTIFIER);
    expect(consoleLogSpy).not.toHaveBeenCalled();
    expect(consoleErrorSpy).not.toHaveBeenCalled();
    expect(consoleWarnSpy).not.toHaveBeenCalled();
  });

  it("forwards Coach content and its pseudonym but no Rep Today identity fields", async () => {
    await worker.fetch(coachRequest({ context: CONTEXT, message: "how do I do a pistol squat?" }), ENV);

    const upstreamBody = JSON.parse(fetchSpy.mock.calls[0][1].body);
    const sentPrompt = upstreamBody.input;
    // The user's message and the audited context reach the model, the context in the app's words...
    expect(sentPrompt).toContain("how do I do a pistol squat?");
    expect(sentPrompt).toContain("Strength Phase: not earned yet.");
    // ...and nothing identifying is anywhere in the outbound request.
    const wholeRequest = JSON.stringify(fetchSpy.mock.calls[0][1]);
    for (const forbidden of ["installId", "install_id", "idfa", "appleId", "apple_id", "email"]) {
      expect(wholeRequest.toLowerCase()).not.toContain(forbidden.toLowerCase());
    }
  });

  it("rejects a missing message before any upstream call", async () => {
    const response = await worker.fetch(coachRequest({ context: CONTEXT }), ENV);
    expect(response.status).toBe(400);
    expect((await response.json()).error).toBe("invalid_message");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("rejects an empty/whitespace message before any upstream call", async () => {
    const response = await worker.fetch(coachRequest({ context: CONTEXT, message: "   " }), ENV);
    expect(response.status).toBe(400);
    expect((await response.json()).error).toBe("invalid_message");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("rejects a missing or non-object context before any upstream call", async () => {
    const missing = await worker.fetch(coachRequest({ message: "hi" }), ENV);
    expect(missing.status).toBe(400);
    expect((await missing.json()).error).toBe("invalid_context");

    const wrongType = await worker.fetch(coachRequest({ context: "nope", message: "hi" }), ENV);
    expect(wrongType.status).toBe(400);
    expect((await wrongType.json()).error).toBe("invalid_context");

    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("rejects a missing or non-pseudonymous safety identifier before any upstream call", async () => {
    const missing = await worker.fetch(
      coachRequest(
        { context: CONTEXT, message: "hi" },
        { includeSafetyIdentifier: false }
      ),
      ENV
    );
    expect(missing.status).toBe(400);
    expect((await missing.json()).error).toBe("invalid_safety_identifier");

    for (const safetyIdentifier of [
      "00000000-0000-4000-8000-000000000001",
      "person@example.com",
      "coach-not-a-uuid",
    ]) {
      const invalid = await worker.fetch(
        coachRequest({ context: CONTEXT, message: "hi", safetyIdentifier }),
        ENV
      );
      expect(invalid.status).toBe(400);
      expect((await invalid.json()).error).toBe("invalid_safety_identifier");
    }

    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("rejects an over-length message before any upstream call", async () => {
    const longMessage = "a".repeat(2001);
    const response = await worker.fetch(coachRequest({ context: CONTEXT, message: longMessage }), ENV);
    expect(response.status).toBe(413);
    expect((await response.json()).error).toBe("message_too_long");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("rejects an oversized body before parsing or any upstream call", async () => {
    // A body larger than the 32 KiB cap - built without a giant valid message so the size cap, not
    // the message cap, is what fires.
    const huge = JSON.stringify({ context: CONTEXT, message: "hi", padding: "x".repeat(40 * 1024) });
    const response = await worker.fetch(coachRequest(huge), ENV);
    expect(response.status).toBe(413);
    expect((await response.json()).error).toBe("payload_too_large");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("rejects an oversized body declared only via content-length, before buffering", async () => {
    const response = await worker.fetch(
      coachRequest({ context: CONTEXT, message: "hi" }, { headers: { "content-length": String(64 * 1024) } }),
      ENV
    );
    expect(response.status).toBe(413);
    expect((await response.json()).error).toBe("payload_too_large");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("rejects invalid JSON before any upstream call", async () => {
    const response = await worker.fetch(coachRequest("{ not json"), ENV);
    expect(response.status).toBe(400);
    expect((await response.json()).error).toBe("invalid_json");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("returns not_configured (never leaking details) when the API key is absent, without an upstream call", async () => {
    const response = await worker.fetch(coachRequest({ context: CONTEXT, message: "hi" }), {});
    expect(response.status).toBe(500);
    expect((await response.json()).error).toBe("not_configured");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("maps an upstream failure to a 502 without leaking detail", async () => {
    fetchSpy.mockResolvedValueOnce({ ok: false, status: 529 });
    const response = await worker.fetch(coachRequest({ context: CONTEXT, message: "hi" }), ENV);
    expect(response.status).toBe(502);
    expect((await response.json()).error).toBe("upstream_error");
  });

  it("returns empty_reply when the Coach model returns no text", async () => {
    fetchSpy.mockResolvedValueOnce(openAIReply("   "));
    const response = await worker.fetch(coachRequest({ context: CONTEXT, message: "hi" }), ENV);
    expect(response.status).toBe(502);
    expect((await response.json()).error).toBe("empty_reply");
  });

  it("maps a refusal to the dedicated safety outcome without exposing provider text", async () => {
    const providerRefusal = "Provider-authored refusal that must stay behind the proxy.";
    fetchSpy.mockResolvedValueOnce(openAIRefusal(providerRefusal));

    const response = await worker.fetch(coachRequest({ context: CONTEXT, message: "unsafe request" }), ENV);
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({ outcome: "safety_refusal" });
    expect(JSON.stringify(body)).not.toContain(providerRefusal);
  });

  it("treats a refusal as authoritative when output text is also present", async () => {
    fetchSpy.mockResolvedValueOnce(openAIRefusal("Provider refusal", "Text that must not escape"));

    const response = await worker.fetch(coachRequest({ context: CONTEXT, message: "unsafe request" }), ENV);

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ outcome: "safety_refusal" });
  });

  it("treats content-filtered incomplete output as a safety outcome before exposing text", async () => {
    const providerText = "Partial provider text that must not escape";
    fetchSpy.mockResolvedValueOnce({
      ok: true,
      async json() {
        return {
          status: "incomplete",
          incomplete_details: { reason: "content_filter" },
          output: [{ type: "message", content: [{ type: "output_text", text: providerText }] }],
        };
      },
    });

    const response = await worker.fetch(coachRequest({ context: CONTEXT, message: "unsafe request" }), ENV);
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({ outcome: "safety_refusal" });
    expect(JSON.stringify(body)).not.toContain(providerText);
  });

  it.each(["failed", "cancelled", "queued", "in_progress"])(
    "rejects a %s response before exposing partial output",
    async (status) => {
      const providerText = `Partial output from ${status}`;
      fetchSpy.mockResolvedValueOnce({
        ok: true,
        async json() {
          return {
            status,
            error: null,
            output: [{ type: "message", content: [{ type: "output_text", text: providerText }] }],
          };
        },
      });

      const response = await worker.fetch(coachRequest({ context: CONTEXT, message: "hi" }), ENV);
      const body = await response.json();

      expect(response.status).toBe(502);
      expect(body).toEqual({ error: "upstream_error" });
      expect(JSON.stringify(body)).not.toContain(providerText);
    }
  );

  it("rejects a response error before exposing output", async () => {
    const providerText = "Output paired with an error";
    fetchSpy.mockResolvedValueOnce({
      ok: true,
      async json() {
        return {
          status: "completed",
          error: { code: "server_error", message: "Provider detail" },
          output: [{ type: "message", content: [{ type: "output_text", text: providerText }] }],
        };
      },
    });

    const response = await worker.fetch(coachRequest({ context: CONTEXT, message: "hi" }), ENV);
    const body = await response.json();

    expect(response.status).toBe(502);
    expect(body).toEqual({ error: "upstream_error" });
    expect(JSON.stringify(body)).not.toContain(providerText);
    expect(JSON.stringify(body)).not.toContain("Provider detail");
  });

  it("returns partial output when generation reaches the output-token limit", async () => {
    fetchSpy.mockResolvedValueOnce({
      ok: true,
      async json() {
        return {
          status: "incomplete",
          error: null,
          incomplete_details: { reason: "max_output_tokens" },
          output: [{ type: "message", content: [{ type: "output_text", text: "Useful partial reply" }] }],
        };
      },
    });

    const response = await worker.fetch(coachRequest({ context: CONTEXT, message: "hi" }), ENV);

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ reply: "Useful partial reply" });
  });

  // US-AC02: the refined persona. The system prompt is where the target intents, the app's voice, and
  // the never-a-workout safety framing live, so assert the outbound system carries them - the coach's
  // behavior is steered here, not by app-side post-processing.
  it("sends a persona that forbids generating a workout and names the target intents and voice", async () => {
    await worker.fetch(coachRequest({ context: CONTEXT, message: "why squats today?" }), ENV);

    const upstreamBody = JSON.parse(fetchSpy.mock.calls[0][1].body);
    const system = upstreamBody.instructions.toLowerCase().replace(/\s+/g, " ");

    // The load-bearing safety invariant (AC3): talking only, never a generated/edited workout.
    expect(system).toContain("never generate");
    expect(system).toContain("talking only");
    // The target intents (AC2): why-this-workout, form, injury-with-flag, and boredom/variety.
    expect(system).toContain("explain the app's reasoning from the context - the area they have gone longest without");
    expect(system).toContain("form");
    expect(system).toContain("flag that area themselves");
    expect(system).toContain("never diagnose");
    expect(system).toContain("variety");
    // Voice/safety framing (AC5): identity-framed, never shaming/gamified.
    expect(system).toContain("identity-framed");
    expect(system).toContain("never");
    expect(system).toContain("shaming");
  });

  // US-AC08: the model-side half of "the coach's language never implies it has removed movements".
  // The app-side half - the routing offer's own copy - is pinned in InjuryRoutingEvidenceTests; a
  // model's free text cannot be pinned, so this asserts the instruction that steers it.
  it("sends a persona that forbids setting or claiming an injury filter", async () => {
    await worker.fetch(coachRequest({ context: CONTEXT, message: "my knee hurts on squats" }), ENV);

    // The prompt is authored as wrapped lines joined with a space, so runs of whitespace are collapsed
    // here to let an assertion span a wrap without pinning where the wrap happens to fall.
    const system = JSON.parse(fetchSpy.mock.calls[0][1].body).instructions.toLowerCase().replace(/\s+/g, " ");

    // Only the user sets the flag, and only in the app's injury control.
    expect(system).toContain("injury settings");
    expect(system).toContain("cannot set, clear, or read that flag");
    expect(system).toContain("only the user can");
    // And it must never narrate a change it did not make.
    expect(system).toContain("never say or imply that you have flagged it, removed a movement, or changed anything");
  });

  // US-AN02: the coach narrates the strength-journey analytics and may offer a bounded preference
  // nudge, but never edits the workout or claims to have changed anything itself.
  it("sends a persona that narrates the strength journey and offers only a bounded preference", async () => {
    await worker.fetch(coachRequest({ context: CONTEXT, message: "how am I doing?" }), ENV);

    const system = JSON.parse(fetchSpy.mock.calls[0][1].body).instructions.toLowerCase().replace(/\s+/g, " ");

    // It is told the strength-journey trend is in the context, and to narrate a concrete insight.
    expect(system).toContain("strength-journey trend");
    expect(system).toContain("how am i doing");
    expect(system).toContain("has gone flat");
    // The action it may offer is a preference the app applies - never a workout edit, never a claim.
    expect(system).toContain("leaning the program toward");
    expect(system).toContain("never say you have already changed anything");
  });

  it("teaches the four foundations and side-aware Legs narration in the emitted model request", async () => {
    await worker.fetch(coachRequest({ context: CONTEXT, message: "how am I doing?" }), ENV);

    const upstreamBody = JSON.parse(fetchSpy.mock.calls[0][1].body);
    const system = upstreamBody.instructions.toLowerCase().replace(/\s+/g, " ");

    expect(system).toContain("four foundations are push, pull, legs, and core");
    expect(system).toContain("squat side and the hinge side");
    expect(system).toContain("pull counts only its row ladder; other pull work in a session does not clear the foundation");
    expect(system).toContain("the hinge side of your legs has been flat about 3 weeks");
    expect(system).toContain("never as standalone foundations");
    // The model is handed each foundation by the name the Progress tab gives it, Legs as its two
    // sides, so it has no key to translate.
    const standing = summaryOf(upstreamBody).split("\n").filter((line) => line.includes(", Tier "));
    expect(standing.map((line) => line.slice(2, line.indexOf(":")))).toEqual([
      "Push", "Pull", "Legs, Squat side", "Legs, Hinge side", "Core",
    ]);
  });

  // The app shows the user "Tier 2 of 4", so "tier" is the app's word and the Coach may say it. The
  // words the app never shows in that sense are one list, and for each the instructions say what to
  // use instead.
  it("tells the Coach what to say instead of each listed word and keeps the app's own vocabulary", async () => {
    await worker.fetch(coachRequest({ context: CONTEXT, message: "how am I doing?" }), ENV);

    const upstreamBody = JSON.parse(fetchSpy.mock.calls[0][1].body);
    const { wordsToAvoid } = splitInstructions(upstreamBody.instructions);
    const system = upstreamBody.instructions.toLowerCase().replace(/\s+/g, " ");

    expect(INTERNAL_WORDS.length).toBeGreaterThan(0);
    for (const { word, say } of INTERNAL_WORDS) {
      if (say === null) {
        // Kept out of what the Coach is given without being named to it.
        expect(saysPhrase(upstreamBody.instructions, word), word).toBe(false);
        continue;
      }
      expect(wordsToAvoid, word).toContain(`'${word}'`);
      expect(wordsToAvoid, word).toContain(say);
    }

    // The user-facing vocabulary the Progress tab already shows, "tier" included.
    expect(listedWordsIn("tier tiers Tier 2 of 4")).toEqual([]);
    expect(system).toContain("'consistency', 'tier 2 of 4', 'next tier in reach', 'strength phase', and 'not started yet'");
    expect(system).toContain("the area you've gone longest without");
    expect(system).toContain("the app rotates which areas they train and avoids repeating recent ones");
    expect(system).toContain(
      "leaning the program toward exactly that one (for example the hinge side of legs)",
    );
  });

  it("uses no listed word in the instructions outside the sentence that says what to use instead", async () => {
    await worker.fetch(coachRequest({ context: CONTEXT, message: "how am I doing?" }), ENV);

    const { rest } = splitInstructions(JSON.parse(fetchSpy.mock.calls[0][1].body).instructions);

    expect(listedWordUses(rest)).toEqual([]);
    // "unlock" survives in exactly the sense the app uses it in: what the Strength Phase opens.
    expect(rest).toContain("harder skills unlock through sustained consistency");
    expect(listedWordUses("New tiers unlock as they progress.")).toEqual([
      "unlock: New tiers unlock as they progress.",
    ]);
    // The matcher is not vacuous, and reads whole words only.
    expect(listedWordsIn("a per-line trend on a progression chain")).toEqual(["chain", "line"]);
    expect(listedWordsIn("chainPositions, hasNextTier")).toEqual(["chain"]);
    expect(listedWordsIn("a discipline-first app; Incline Push-Up; phase: discipline")).toEqual([]);
    expect(listedWordsIn("You are in the Discipline Phase.")).toEqual(["Discipline Phase"]);
  });

  // The reproduction as a regression test. Each file is a request the app really builds (the first is
  // the reported case: a beginner on the first movement of every foundation). A model repeats the
  // words it is given, so nothing it is handed for these may be a listed word.
  it("gives the model no listed word for any request the app builds", async () => {
    expect(APP_REQUESTS.map(({ file }) => file)).toEqual([
      "beginner-first-tier.json", "no-history.json", "strength-climbing-and-flat.json",
    ]);

    for (const { file, body } of APP_REQUESTS) {
      fetchSpy.mockClear();
      const response = await worker.fetch(coachRequest(body), ENV);
      expect(response.status, file).toBe(200);

      const upstreamBody = JSON.parse(fetchSpy.mock.calls[0][1].body);
      const summary = summaryOf(upstreamBody);

      // The whole prompt: the summary, and the made-up message these fixtures carry.
      expect(listedWordsIn(upstreamBody.input), file).toEqual([]);
      expect(listedWordUses(splitInstructions(upstreamBody.instructions).rest), file).toEqual([]);

      // The request's own JSON never reaches the model: no syntax, and none of its field names.
      expect(summary, file).not.toMatch(/[{}"\[\]]/);
      const fieldNames = compoundFieldNamesIn(body.context);
      expect(fieldNames, file).toEqual(expect.arrayContaining(["chainPositions", "chainLength", "hasNextTier"]));
      for (const fieldName of fieldNames) {
        expect(summary, `${file}: ${fieldName}`).not.toContain(fieldName);
      }

      // The facts still arrive: every movement the app named, and the minutes.
      for (const { currentExercise } of body.context.chainPositions) {
        if (currentExercise) {
          expect(summary, file).toContain(currentExercise);
        }
      }
      expect(summary, file).toContain(`Requested minutes: ${body.context.requestedMinutes}.`);
    }
  });

  it("hands the model the reported beginner's standing as the Progress tab words it", async () => {
    const { body } = APP_REQUESTS.find(({ file }) => file === "beginner-first-tier.json");
    await worker.fetch(coachRequest(body), ENV);

    const lines = summaryOf(JSON.parse(fetchSpy.mock.calls[0][1].body)).split("\n");

    expect(lines).toContain("Strength Phase: not earned yet.");
    const from = lines.indexOf("Where they stand in each foundation:");
    const standing = lines.slice(from + 1, from + 6);
    expect(standing.map((line) => line.slice(0, line.indexOf(":")))).toEqual([
      "- Push", "- Pull", "- Legs, Squat side", "- Legs, Hinge side", "- Core",
    ]);
    // Every foundation on its first tier, in the card's own form.
    for (const line of standing) {
      expect(line).toMatch(/^- [A-Za-z, ]+: .+, Tier 1 of \d+( - next tier in reach)?$/);
    }
  });

  it("writes every fact of a request in the app's words and nothing else", async () => {
    await worker.fetch(coachRequest({ context: CONTEXT, message: "how am I doing?" }), ENV);

    expect(JSON.parse(fetchSpy.mock.calls[0][1].body).input).toBe(
      [
        "User's progress context (a non-identifying summary):",
        "Strength Phase: not earned yet.",
        "Requested minutes: 15.",
        "Where they stand in each foundation:",
        "- Push: Standard Push-Up, Tier 3 of 7 - next tier in reach",
        "- Pull: Wall Scapular Pull, Tier 1 of 3 - next tier in reach",
        "- Legs, Squat side: Bodyweight Squat, Tier 2 of 6 - next tier in reach",
        "- Legs, Hinge side: Glute Bridge, Tier 1 of 5 - next tier in reach",
        "- Core: Dead Bug, Tier 2 of 5 - next tier in reach",
        "Movement patterns in their recent sessions, most recent first: Push, Core, Squat.",
        "Consistency: 72, rising.",
        "Strength journey:",
        "- Legs, Hinge side: flat, 3 weeks at its current tier, has moved up a tier before",
        "",
        "User's message:",
        "how am I doing?",
      ].join("\n"),
    );
  });

  it("states the Strength Phase as earned, a top tier without a next one, and a first week in the singular", async () => {
    const context = {
      phase: "strength",
      requestedMinutes: 30,
      chainPositions: [
        { pattern: "pull", currentExercise: "Single-Arm Supine Floor Row", tier: 3, chainLength: 3, hasNextTier: false },
      ],
      recentPatterns: [],
      consistency: { currentScore: 0, direction: "new" },
      strengthJourney: [{ pattern: "pull", trend: "climbing", weeksAtCurrentTier: 1, hasAdvanced: true }],
    };
    await worker.fetch(coachRequest({ context, message: "hi" }), ENV);

    expect(summaryOf(JSON.parse(fetchSpy.mock.calls[0][1].body)).split("\n").slice(1)).toEqual([
      "Strength Phase: earned.",
      "Requested minutes: 30.",
      "Where they stand in each foundation:",
      "- Pull: Single-Arm Supine Floor Row, Tier 3 of 3",
      "Movement patterns in their recent sessions, most recent first: none yet.",
      "Consistency: 0, no trend yet.",
      "Strength journey:",
      "- Pull: climbing, 1 week at its current tier, has moved up a tier before",
    ]);
  });

  // The context is validated only as an object, so anything can arrive in it. What the Worker does not
  // recognize is dropped, never handed on, and a value cannot add lines of its own.
  it("leaves out what a request does not carry and drops what it does not recognize", async () => {
    const context = {
      phase: "frontier",
      requestedMinutes: "15",
      chainPositions: [
        null,
        7,
        { pattern: "engine", currentExercise: "Stalest Chain", tier: 1, chainLength: 1 },
        { pattern: "push", currentExercise: "Wall\nPush-Up\n- Core: on the line", tier: 1, chainLength: 4, hasNextTier: "yes", chain: "x" },
        { pattern: "hinge", currentExercise: "Glute Bridge", tier: 0, chainLength: -2 },
        { pattern: "core" },
      ],
      recentPatterns: ["engine", "push", 3],
      consistency: "steady",
      strengthJourney: [{ pattern: "hinge", trend: "stalest" }, { pattern: "chain", trend: "flat" }],
      engine: { chain: "frontier" },
    };
    await worker.fetch(coachRequest({ context, message: "hi" }), ENV);

    expect(summaryOf(JSON.parse(fetchSpy.mock.calls[0][1].body)).split("\n").slice(1)).toEqual([
      "Where they stand in each foundation:",
      // A movement's name is the one free text passed on, as a single line.
      "- Push: Wall Push-Up - Core: on the line, Tier 1 of 4",
      "- Legs, Hinge side: Glute Bridge",
      "- Core: Not started yet",
      "Movement patterns in their recent sessions, most recent first: Push.",
      "Strength journey: nothing to read yet.",
    ]);

    // An empty context still reaches the model, with nothing invented for it.
    fetchSpy.mockClear();
    await worker.fetch(coachRequest({ context: {}, message: "hi" }), ENV);
    expect(JSON.parse(fetchSpy.mock.calls[0][1].body).input).toBe(
      "User's progress context (a non-identifying summary):\n\nUser's message:\nhi",
    );
  });

  it("sends a neutral not-started rule and marks recent patterns as not proof of completed work", async () => {
    const context = {
      ...CONTEXT,
      chainPositions: CONTEXT.chainPositions.map((position) =>
        position.pattern === "pull"
          ? { pattern: "pull", tier: 0, chainLength: 0, hasNextTier: false }
          : position,
      ),
      recentPatterns: ["pull", "push", "squat"],
    };
    await worker.fetch(coachRequest({ context, message: "how am I doing?" }), ENV);

    const upstreamBody = JSON.parse(fetchSpy.mock.calls[0][1].body);
    const system = upstreamBody.instructions.toLowerCase().replace(/\s+/g, " ");
    const summary = summaryOf(upstreamBody).split("\n");

    // The not-started foundation reaches the model in the Progress tab's words, beside recent sessions
    // that include it.
    expect(summary).toContain("- Pull: Not started yet");
    expect(summary).toContain("Movement patterns in their recent sessions, most recent first: Pull, Push, Squat.");
    expect(system).toContain(
      "a foundation the summary shows as 'not started yet' has no tracked progress yet: " +
        "say its progress hasn't started yet - 'your pull and core progress hasn't started yet'. " +
        "that is a statement about tracked progress only, never a claim about whether the user did or did not do related work.",
    );
    expect(system).toContain(
      "the recent movement patterns are not foundation names: " +
        "they are the patterns that appeared in recent sessions, which can include skipped steps. " +
        "never assert from them that the user completed specific work.",
    );
    expect(system).toContain("movement patterns that appeared in their recent sessions");
    expect(system).not.toContain("trained recently");
    expect(system).toContain("never call it missing data or a gap in what you can see.");
    expect(system).toContain("a not-started foundation is not a stall, so never call it flat or stuck.");
    expect(system).not.toContain("build toward");
    expect(system).toContain("name any foundation with no progress yet, worded as the not-started rule above says");
    // The rule that the app owns every session survives the vocabulary change.
    expect(system).toContain("the app builds every session");
    expect(system).toContain("the app owns every session");
    expect(system).toContain("talking only");
  });
});

describe("abuse gate", () => {
  const GATED_ENV = { OPENAI_API_KEY: "sk-openai-test", CLIENT_SHARED_SECRET: "s3cret" };

  it("rejects a wrong bearer with 401 before any upstream call", async () => {
    const response = await worker.fetch(
      coachRequest({ context: CONTEXT, message: "hi" }, { headers: { authorization: "Bearer wrong" } }),
      GATED_ENV
    );
    expect(response.status).toBe(401);
    expect((await response.json()).error).toBe("unauthorized");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("accepts the correct bearer", async () => {
    const response = await worker.fetch(
      coachRequest({ context: CONTEXT, message: "hi" }, { headers: { authorization: "Bearer s3cret" } }),
      GATED_ENV
    );
    expect(response.status).toBe(200);
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });
});

describe("routing and method", () => {
  it("rejects non-POST with 405", async () => {
    const response = await worker.fetch(new Request(COACH_URL, { method: "GET" }), ENV);
    expect(response.status).toBe(405);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("still serves the Variety Language route unchanged", async () => {
    fetchSpy.mockResolvedValueOnce(anthropicReply("Today leans into mobility."));
    const request = new Request(VARIETY_URL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ today: "mobility", yesterday: "strength" }),
    });
    const response = await worker.fetch(request, ENV);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ line: "Today leans into mobility." });
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });

  it("rejects an invalid Variety Language pillar before any upstream call", async () => {
    const request = new Request(VARIETY_URL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ today: "bogus" }),
    });
    const response = await worker.fetch(request, ENV);
    expect(response.status).toBe(400);
    expect((await response.json()).error).toBe("invalid_today");
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});
