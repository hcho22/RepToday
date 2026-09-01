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
    { pattern: "squat", currentExercise: "Bodyweight Squat", tier: 2, chainLength: 6, hasNextTier: true },
  ],
  recentPatterns: ["push", "core", "squat"],
  consistency: { currentScore: 72, direction: "rising" },
};

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
  fetchSpy = vi.fn(async () => openAIReply("Because squats were your stalest pattern this week."));
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
    expect(json).toEqual({ reply: "Because squats were your stalest pattern this week." });

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
    // The user's message and the audited context reach the model...
    expect(sentPrompt).toContain("how do I do a pistol squat?");
    expect(sentPrompt).toContain('"phase":"discipline"');
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
    const system = upstreamBody.instructions.toLowerCase();

    // The load-bearing safety invariant (AC3): talking only, never a generated/edited workout.
    expect(system).toContain("never generate");
    expect(system).toContain("talking only");
    // The target intents (AC2): why-this-workout, form, injury-with-flag, and boredom/variety.
    expect(system).toContain("stalest");
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
