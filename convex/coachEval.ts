import { v } from "convex/values";
import { internalAction } from "./_generated/server";
import { catalogMessage, COACH_INSTRUCTIONS, contextMessage } from "./coachPrompt";
import { openAIRequestBody } from "./coachModel";
import { parseToolCalls } from "./coachTools";

/**
 * The Coach model evaluation (M4, Open Question 3), re-runnable on a deployment that holds a provider
 * key: `npx convex run coachEval:run '{"model":"gpt-5.6-luna"}'`.
 *
 * Twelve fixed turns from one synthetic user (no real person's data) cover each tool, a turn that
 * needs no tool, an adult diet question, and a request for a move the Coach must not offer (a
 * de-load). Each turn is scored on whether the model chose exactly the expected tool - parsed through
 * the same validator production uses - or, where none is expected, answered in words without one; it
 * reports latency and token counts so the per-turn cost can
 * be worked out from the provider's prices. Internal only: no client can call it, and it makes at most
 * one model call per case.
 */

declare const process: { readonly env: Readonly<Record<string, string | undefined>> };

const TODAY = {
  localDate: "2026-11-11",
  utcOffsetMinutes: -480,
  kind: "train" as const,
  trainingDay: "push",
  minutes: 20,
  movements: [
    { id: "push_incline", name: "Incline Push-Up" },
    { id: "push_pike", name: "Pike Push-Up" },
    { id: "core_dead_bug", name: "Dead Bug" },
  ],
};

const CONTEXT = contextMessage({
  ageGroup: "adult",
  profile: {
    phase: "discipline",
    consistency: { score: 61, weeklyGoal: 3, totalWorkoutsCompleted: 14 },
    duration: { defaultMinutes: 20 },
    profile: { fitnessLevel: "intermediate", injuries: ["wrists"] },
  },
  focusAreas: ["chest"],
  logs: [
    {
      completedAt: Date.UTC(2026, 10, 10, 15),
      durationMinutes: 20,
      perceivedDifficulty: "just_right",
      exercises: [
        { exerciseId: "squat_bodyweight", movementPattern: "squat", role: "main", skipped: false, completedSets: [{ reps: 20 }, { reps: 20 }, { reps: 20 }, { reps: 20 }] },
      ],
    },
  ],
  activities: [],
  customWorkouts: [],
  today: TODAY,
});

const REST_CONTEXT = CONTEXT.replace("- Today is a Push Training Day of 20 minutes.", "- Today is a Rest Day; the next Training Day is Push.");

type Case = { id: string; message: string; expect: string | null; rest?: boolean };

const CASES: Case[] = [
  { id: "outside-run", message: "I ran 5k this morning, about 30 minutes.", expect: "outsideActivity" },
  { id: "outside-swim-yesterday", message: "Swam for 45 minutes yesterday, can you log that?", expect: "outsideActivity" },
  { id: "rest-today", message: "I'm wiped out. Can I just rest today?", expect: "restChoice" },
  { id: "train-anyway", message: "It says rest day but I feel great - I want to train today.", expect: "restChoice", rest: true },
  { id: "length", message: "I only have 10 minutes today.", expect: "todayLength" },
  { id: "swap", message: "Please swap out the pike push-ups today, I don't like them.", expect: "swapMovement" },
  { id: "focus", message: "Set my focus areas to glutes and abs.", expect: "focusAreas" },
  { id: "reminder", message: "Remind me to train at 7am on weekdays.", expect: "reminder" },
  { id: "custom-workout", message: "Write me a 15 minute workout I can do in a hotel room.", expect: "customWorkout" },
  { id: "form-question", message: "How do I do a proper bodyweight squat?", expect: null },
  { id: "adult-diet", message: "How much protein should I be eating?", expect: null },
  { id: "deload-refused", message: "Put me on a deload week and reset my progress.", expect: null },
];

export const run = internalAction({
  args: { model: v.string(), effort: v.optional(v.string()) },
  handler: async (_ctx, { model, effort }) => {
    const key = process.env.OPENAI_API_KEY;
    if (key === undefined || key.length === 0) {
      throw new Error("OPENAI_API_KEY is not set on this deployment.");
    }
    const results = [];
    for (const testCase of CASES) {
      const body = openAIRequestBody(
        {
          instructions: COACH_INSTRUCTIONS,
          input: [
            { role: "developer", content: `${testCase.rest ? REST_CONTEXT : CONTEXT}\n\n${catalogMessage()}` },
            { role: "user", content: testCase.message },
          ],
          safetyIdentifier: "rt-eval",
        },
        model,
      );
      if (effort !== undefined) body.reasoning = { effort: effort as "low" };
      const started = Date.now();
      const response = await fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
        body: JSON.stringify(body),
      });
      const elapsedMs = Date.now() - started;
      const json = (await response.json()) as Record<string, any>;
      const output = Array.isArray(json.output) ? json.output : [];
      const calls = output
        .filter((item: any) => item?.type === "function_call")
        .map((item: any) => ({ name: String(item.name), arguments: String(item.arguments) }));
      const text = output
        .filter((item: any) => item?.type === "message")
        .flatMap((item: any) => item.content ?? [])
        .filter((block: any) => block?.type === "output_text")
        .map((block: any) => String(block.text))
        .join("")
        .trim();
      const proposals = parseToolCalls(calls, TODAY.movements, () => "eval");
      const kinds = proposals.map((proposal) => proposal.kind);
      // A tool call needs no text of its own (the server adds a line per proposal kind); a turn with no
      // tool must answer in words.
      const pass = testCase.expect === null ? kinds.length === 0 && text.length > 0 : kinds.length === 1 && kinds[0] === testCase.expect;
      results.push({
        id: testCase.id,
        status: response.status,
        expected: testCase.expect,
        got: kinds,
        rawTools: calls.map((call: { name: string }) => call.name),
        pass,
        elapsedMs,
        inputTokens: json.usage?.input_tokens ?? null,
        cachedTokens: json.usage?.input_tokens_details?.cached_tokens ?? null,
        outputTokens: json.usage?.output_tokens ?? null,
        reply: text.slice(0, 240),
        proposals,
      });
    }
    return {
      model,
      effort: effort ?? "low",
      passed: results.filter((result) => result.pass).length,
      total: results.length,
      results,
    };
  },
});
