import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import schema from "./schema";
import { api } from "./_generated/api";
import { COACH_TOOL_NAMES } from "./coachTools";
import { CRISIS_SUPPORT_REPLY, DIET_DECLINE_REPLY, EATING_SUPPORT_REPLY } from "./coachSafety";
import { DEFAULT_COACH_MODEL } from "./coachModel";
import type { SyncChange } from "./sync";

/**
 * The Coach agent on Convex (M4, US-CA01/US-CA03/US-CA07): one turn as a Clerk-authenticated action
 * that reads the user's records server-side, checks the entitlement on every turn, keeps the
 * conversation, and turns tool calls into proposals. OpenAI is a recorded `fetch` stub, so each test
 * can read exactly what would have been sent and nothing leaves the process.
 */

declare const process: { env: Record<string, string | undefined> };

const modules: Record<string, () => Promise<any>> = Object.fromEntries(
  Object.entries({
    ...import.meta.glob("./**/*.ts"),
    ...import.meta.glob("./**/*.js"),
  }).filter(([path]) => !path.endsWith(".d.ts") && !path.endsWith(".test.ts")),
);

const ALICE = { subject: "user_alice", tokenIdentifier: "https://clerk.test|user_alice", issuer: "https://clerk.test" };
const BOB = { subject: "user_bob", tokenIdentifier: "https://clerk.test|user_bob", issuer: "https://clerk.test" };
const DAY = 24 * 60 * 60 * 1000;
const savedEnv = { ...process.env };

type ModelCall = { body: Record<string, any> };
let modelCalls: ModelCall[];
let nextResponse: () => unknown;

function modelReply(text: string, toolCalls: { name: string; arguments: unknown }[] = []) {
  return {
    status: "completed",
    output: [
      ...(text.length > 0 ? [{ type: "message", role: "assistant", content: [{ type: "output_text", text }] }] : []),
      ...toolCalls.map((call, index) => ({ type: "function_call", call_id: `call_${index}`, name: call.name, arguments: JSON.stringify(call.arguments) })),
    ],
  };
}

beforeEach(() => {
  process.env.OPENAI_API_KEY = "sk-test-placeholder";
  delete process.env.COACH_MODEL_STUB;
  delete process.env.COACH_MODEL;
  delete process.env.COACH_DAILY_TURNS_PER_ACCOUNT;
  modelCalls = [];
  nextResponse = () => modelReply("You're someone who shows up.");
  vi.stubGlobal(
    "fetch",
    vi.fn(async (_url: string, init?: RequestInit) => {
      modelCalls.push({ body: JSON.parse(String(init?.body)) });
      return new Response(JSON.stringify(nextResponse()), { status: 200, headers: { "content-type": "application/json" } });
    }),
  );
});

afterEach(() => {
  vi.unstubAllGlobals();
  for (const key of ["OPENAI_API_KEY", "COACH_MODEL_STUB", "COACH_MODEL", "COACH_DAILY_TURNS_PER_ACCOUNT"]) {
    if (savedEnv[key] === undefined) delete process.env[key];
    else process.env[key] = savedEnv[key];
  }
});

function profilePayload(age: number | null, extra: Record<string, unknown> = {}) {
  return JSON.stringify({
    id: "local-user-1",
    displayName: "Riley Quinn",
    phase: "discipline",
    consistency: { weeklyGoal: 3, score: 72.4, totalWorkoutsCompleted: 9 },
    duration: { defaultMinutes: 20 },
    profile: {
      ...(age === null ? {} : { age }),
      sex: "female",
      heightCm: 171,
      weightKg: 64,
      fitnessLevel: "beginner",
      sitsLong: true,
      injuries: ["knees"],
      typicalAvailableMinutes: 20,
    },
    ...extra,
  });
}

async function seedUser(t: ReturnType<typeof convexTest>, who: typeof ALICE, options: { age?: number | null; premium?: "active" | "expired" | "revoked" | "none" } = {}) {
  const changes: SyncChange[] = [
    { table: "profile", recordId: "local-user-1", clientUpdatedAt: 1, payload: profilePayload(options.age === undefined ? 34 : options.age), focusAreas: ["chest"] },
    {
      table: "workoutLog",
      recordId: "L1",
      clientUpdatedAt: 1,
      deleted: false,
      completedAt: Date.now() - DAY,
      payload: JSON.stringify({
        completedAt: Date.now() - DAY,
        durationMinutes: 20,
        perceivedDifficulty: "just_right",
        exercises: [
          { exerciseId: "push_incline", movementPattern: "push", role: "main", skipped: false, completedSets: [{ reps: 15 }, { reps: 15 }, { reps: 15 }, { reps: 15 }] },
        ],
      }),
    },
  ];
  await t.withIdentity(who).mutation(api.sync.push, { changes });
  const premium = options.premium ?? "active";
  if (premium !== "none") {
    await t.run(async (ctx) => {
      await ctx.db.insert("entitlements", {
        ownerId: who.tokenIdentifier,
        originalTransactionId: who === ALICE ? "100" : "200",
        productId: "com.reptoday.app.premium.monthly",
        environment: "Sandbox",
        expiresAt: premium === "expired" ? Date.now() - DAY : Date.now() + 30 * DAY,
        ...(premium === "revoked" ? { revokedAt: Date.now() - 1000 } : {}),
        lastSignedAt: 1,
        updatedAt: 1,
      });
    });
  }
}

const TODAY = {
  localDate: "2026-11-11",
  utcOffsetMinutes: -480,
  kind: "train" as const,
  trainingDay: "push" as const,
  minutes: 20,
  movements: [
    { id: "push_incline", name: "Incline Push-Up" },
    { id: "core_dead_bug", name: "Dead Bug" },
  ],
};

function send(t: ReturnType<typeof convexTest>, who: typeof ALICE, message: string, id = crypto.randomUUID()) {
  return t.withIdentity(who).action(api.coach.send, { clientMessageId: id, message, today: TODAY });
}

async function expectRefusal(promise: Promise<unknown>, code: string) {
  await expect(promise).rejects.toSatisfy((error: any) => error?.data?.code === code);
}

describe("a Coach turn runs as an authenticated Convex action", () => {
  test("an unauthenticated caller is refused before anything is read or sent", async () => {
    const t = convexTest(schema, modules);
    await expectRefusal(t.action(api.coach.send, { clientMessageId: crypto.randomUUID(), message: "hi" }), "unauthenticated");
    await expectRefusal(t.query(api.coach.history, {}), "unauthenticated");
    await expectRefusal(t.mutation(api.coach.recordProposalOutcome, { messageId: "x", proposalId: "y", status: "applied" }), "unauthenticated");
    expect(modelCalls).toHaveLength(0);
  });

  test("the model is given the user's history, status and injury areas from the server - and no identity", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE);
    const result = await send(t, ALICE, "Why push today?");
    expect(result.coach.text).toBe("You're someone who shows up.");
    expect(modelCalls).toHaveLength(1);
    const body = modelCalls[0].body;
    expect(body.model).toBe(DEFAULT_COACH_MODEL);
    expect(body.store).toBe(false);
    expect(body.tools.map((tool: { name: string }) => tool.name).sort()).toEqual([...COACH_TOOL_NAMES].sort());
    const context = body.input[0].content as string;
    expect(body.input[0].role).toBe("developer");
    expect(context).toContain("Injury areas they flagged: knees");
    expect(context).toContain("Age group: adult");
    expect(context).toContain("Focus Areas: chest");
    expect(context).toContain("Incline Push-Up 4x15");
    expect(context).toContain("Today is a Push Training Day of 20 minutes");
    const sent = JSON.stringify(body);
    for (const identifying of ["Riley", "Quinn", "user_alice", "clerk.test", "171", "64", "34"]) {
      expect(sent).not.toContain(identifying);
    }
    expect(body.safety_identifier).toMatch(/^rt-[0-9a-f]{32}$/);
    expect(body.input[body.input.length - 1]).toEqual({ role: "user", content: "Why push today?" });
  });
});

describe("the entitlement is checked on every turn", () => {
  for (const state of ["none", "expired", "revoked"] as const) {
    test(`${state === "none" ? "free" : state}: refused with not_premium, nothing sent or stored`, async () => {
      const t = convexTest(schema, modules);
      await seedUser(t, ALICE, { premium: state });
      await expectRefusal(send(t, ALICE, "hello"), "not_premium");
      expect(modelCalls).toHaveLength(0);
      expect((await t.withIdentity(ALICE).query(api.coach.history, {})).messages).toEqual([]);
    });
  }

  test("active, then lapsed mid-conversation: the next turn is refused", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE);
    await send(t, ALICE, "first");
    await t.run(async (ctx) => {
      const row = (await ctx.db.query("entitlements").collect())[0];
      await ctx.db.patch(row._id, { expiresAt: Date.now() - 1 });
    });
    await expectRefusal(send(t, ALICE, "second"), "not_premium");
    expect(modelCalls).toHaveLength(1);
  });

  test("an entitlement for another account does not count", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE);
    await seedUser(t, BOB, { premium: "none" });
    await expectRefusal(send(t, BOB, "hello"), "not_premium");
  });
});

describe("conversation memory", () => {
  test("persists, is sent back as context, and stays the owner's own", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE);
    await seedUser(t, BOB);
    await send(t, ALICE, "I like mornings");
    nextResponse = () => modelReply("Mornings it is.");
    await send(t, ALICE, "What did I say?");
    const second = modelCalls[1].body.input as { role: string; content: string }[];
    expect(second.slice(1)).toEqual([
      { role: "user", content: "I like mornings" },
      { role: "assistant", content: "You're someone who shows up." },
      { role: "user", content: "What did I say?" },
    ]);
    const history = await t.withIdentity(ALICE).query(api.coach.history, {});
    expect(history.messages.map((message) => [message.role, message.text])).toEqual([
      ["user", "I like mornings"],
      ["coach", "You're someone who shows up."],
      ["user", "What did I say?"],
      ["coach", "Mornings it is."],
    ]);
    expect((await t.withIdentity(BOB).query(api.coach.history, {})).messages).toEqual([]);
  });

  test("a retried message id returns the stored answer without asking the model again", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE);
    const id = crypto.randomUUID();
    const first = await send(t, ALICE, "hello", id);
    const again = await send(t, ALICE, "hello", id);
    expect(again).toEqual(first);
    expect(modelCalls).toHaveLength(1);
  });

  test("malformed messages are refused", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE);
    await expectRefusal(send(t, ALICE, "   "), "invalid_message");
    await expectRefusal(send(t, ALICE, "x".repeat(2001)), "invalid_message");
    await expectRefusal(t.withIdentity(ALICE).action(api.coach.send, { clientMessageId: "not-a-uuid", message: "hi" }), "invalid_message");
  });
});

describe("tools become proposals; safety-owned moves are unreachable", () => {
  test("every tool's call becomes a validated proposal", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE);
    nextResponse = () =>
      modelReply("Here you go.", [
        { name: "log_outside_activity", arguments: { type: "run", minutes: 30, distance_km: 5, day: "today" } },
        { name: "change_today_length", arguments: { minutes: 10 } },
        { name: "swap_movement", arguments: { movement_id: "push_incline" } },
      ]);
    const result = await send(t, ALICE, "I ran 5k, keep today short and swap the push-ups");
    expect(result.coach.proposals.map((proposal) => proposal.kind)).toEqual(["outsideActivity", "todayLength", "swapMovement"]);
    expect(result.coach.proposals[0]).toMatchObject({ activityType: "run", minutes: 30, distanceMeters: 5000, day: "today", status: "proposed" });
    expect(result.coach.proposals[2]).toMatchObject({ exerciseId: "push_incline", exerciseName: "Incline Push-Up" });

    nextResponse = () =>
      modelReply("", [
        { name: "set_rest_choice", arguments: { choice: "rest_today" } },
        { name: "set_focus_areas", arguments: { areas: ["glutes", "abs", "tail"] } },
        { name: "schedule_reminder", arguments: { time: "07:30", days: ["mon", "fri", "mon"] } },
      ]);
    const second = await send(t, ALICE, "rest, glutes and abs, remind me");
    expect(second.coach.text).toBe("I've put those below for you to confirm.");
    expect(second.coach.proposals).toEqual([
      expect.objectContaining({ kind: "restChoice", choice: "restToday" }),
      expect.objectContaining({ kind: "focusAreas", areas: ["abs", "glutes"] }),
      expect.objectContaining({ kind: "reminder", hour: 7, minute: 30, weekdays: [2, 6] }),
    ]);
  });

  test("a tool outside the closed set - a de-load, a Return, the cold start, an injury flag - is dropped", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE);
    nextResponse = () =>
      modelReply("Done.", [
        { name: "start_deload", arguments: {} },
        { name: "start_return_ramp", arguments: {} },
        { name: "reset_cold_start", arguments: {} },
        { name: "set_injury_flags", arguments: { areas: [] } },
        { name: "set_progression_rate", arguments: { rate: 2 } },
        { name: "swap_movement", arguments: { movement_id: "push_one_arm" } },
      ]);
    const result = await send(t, ALICE, "deload me");
    expect(result.coach.proposals).toEqual([]);
    expect(COACH_TOOL_NAMES).toEqual([
      "log_outside_activity",
      "set_rest_choice",
      "change_today_length",
      "swap_movement",
      "set_focus_areas",
      "schedule_reminder",
      "propose_custom_workout",
    ]);
  });

  test("a Custom Workout is clamped, resolves served catalog ids, and keeps others as text-only steps", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE);
    nextResponse = () =>
      modelReply("Try this.", [
        {
          name: "propose_custom_workout",
          arguments: {
            title: "Knee-Friendly Upper Body",
            note: "Easy on the knees.",
            steps: [
              { name: "push ups", catalog_id: "push_incline", sets: 40, reps: 500, seconds: null, per_side: true, rest_seconds: 900 },
              { name: "Wall Angels", catalog_id: null, sets: 2, reps: null, seconds: 45, per_side: false, rest_seconds: 20 },
              { name: "Retired Crawl", catalog_id: "primal_bear_crawl", sets: 2, reps: 10, seconds: null, per_side: false, rest_seconds: 30 },
            ],
          },
        },
      ]);
    const [proposal] = (await send(t, ALICE, "write me a workout")).coach.proposals;
    expect(proposal.kind).toBe("customWorkout");
    if (proposal.kind !== "customWorkout") throw new Error("unreachable");
    expect(proposal.workout.steps).toEqual([
      { name: "Incline Push-Up", exerciseId: "push_incline", sets: 6, reps: 100, perSide: false, restSeconds: 180 },
      { name: "Wall Angels", sets: 2, seconds: 45, perSide: false, restSeconds: 20 },
      { name: "Retired Crawl", sets: 2, reps: 10, perSide: false, restSeconds: 30 },
    ]);
  });

  test("proposal outcomes are recorded once, in order, and only by the owner", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE);
    await seedUser(t, BOB);
    nextResponse = () => modelReply("Log it?", [{ name: "log_outside_activity", arguments: { type: "swim", minutes: 40, distance_km: null, day: "yesterday" } }]);
    const { coach } = await send(t, ALICE, "I swam yesterday");
    const proposalId = coach.proposals[0].id;
    await expectRefusal(t.withIdentity(BOB).mutation(api.coach.recordProposalOutcome, { messageId: coach.id, proposalId, status: "applied" }), "invalid_change");
    await t.withIdentity(ALICE).mutation(api.coach.recordProposalOutcome, { messageId: coach.id, proposalId, status: "applied" });
    await expectRefusal(t.withIdentity(ALICE).mutation(api.coach.recordProposalOutcome, { messageId: coach.id, proposalId, status: "declined" }), "invalid_change");
    await t.withIdentity(ALICE).mutation(api.coach.recordProposalOutcome, { messageId: coach.id, proposalId, status: "undone" });
    const history = await t.withIdentity(ALICE).query(api.coach.history, {});
    expect(history.messages[1].proposals[0].status).toBe("undone");
    await send(t, ALICE, "thanks");
    expect(modelCalls[1].body.input.some((message: { content: string }) => message.content.includes("the user applied it, then undid it"))).toBe(true);
  });
});

describe("diet guidance with an age rail (FR-12)", () => {
  test("an adult's diet question reaches the model", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE, { age: 30 });
    nextResponse = () => modelReply("Aim for some protein at each meal and drink water through the day.");
    const result = await send(t, ALICE, "How much protein should I eat?");
    expect(modelCalls).toHaveLength(1);
    expect(result.coach.text).toContain("protein");
  });

  for (const [label, age] of [["under 18", 16], ["of unknown age", null]] as const) {
    test(`a user ${label} asking about diet gets the decline and the model is never called`, async () => {
      const t = convexTest(schema, modules);
      await seedUser(t, ALICE, { age });
      const result = await send(t, ALICE, "What should I eat to build muscle?");
      expect(result.coach.text).toBe(DIET_DECLINE_REPLY);
      expect(result.coach.proposals).toEqual([]);
      expect(modelCalls).toHaveLength(0);
    });
  }

  test("a model reply that drifts into diet for a user under 18 is replaced before it is stored", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE, { age: 15 });
    nextResponse = () => modelReply("Great question! Cut down on sugar and add protein.");
    const result = await send(t, ALICE, "How do I get stronger?");
    expect(result.coach.text).toBe(DIET_DECLINE_REPLY);
    const history = await t.withIdentity(ALICE).query(api.coach.history, {});
    expect(history.messages[1].text).toBe(DIET_DECLINE_REPLY);
    expect(modelCalls[0].body.input[0].content).toContain("Age group: under 18");
  });

  test("a minor's plain water question reaches the model and its answer is shown", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE, { age: 16 });
    nextResponse = () => modelReply("Drink a glass or two of water after training, and sip more if you sweated a lot. Staying hydrated helps you recover.");
    const result = await send(t, ALICE, "How much water should I drink after a workout?");
    expect(modelCalls).toHaveLength(1);
    expect(result.coach.text).toContain("glass or two of water");
  });

  test("a minor asking about protein shakes is still declined without the model", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE, { age: 16 });
    const result = await send(t, ALICE, "Should I drink protein shakes?");
    expect(result.coach.text).toBe(DIET_DECLINE_REPLY);
    expect(modelCalls).toHaveLength(0);
  });
});

describe("crisis and disordered-eating redirects at every age (ADR-0019)", () => {
  for (const [label, age] of [["an adult", 30], ["a user under 18", 16], ["a user of unknown age", null]] as const) {
    test(`${label} who speaks of self-harm gets the caring redirect and the model is never called`, async () => {
      const t = convexTest(schema, modules);
      await seedUser(t, ALICE, { age });
      const result = await send(t, ALICE, "I've been thinking about killing myself.");
      expect(result.coach.text).toBe(CRISIS_SUPPORT_REPLY);
      expect(result.coach.proposals).toEqual([]);
      expect(modelCalls).toHaveLength(0);
      const history = await t.withIdentity(ALICE).query(api.coach.history, {});
      expect(history.messages.map((message) => message.text)).toEqual(["I've been thinking about killing myself.", CRISIS_SUPPORT_REPLY]);
    });
  }

  test("a minor's message about starving themselves gets the eating redirect, not the diet decline", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE, { age: 15 });
    const result = await send(t, ALICE, "I've been starving myself to lose weight.");
    expect(result.coach.text).toBe(EATING_SUPPORT_REPLY);
    expect(modelCalls).toHaveLength(0);
  });
});

describe("limits and configuration", () => {
  test("an account's daily turn limit is enforced", async () => {
    const t = convexTest(schema, modules);
    process.env.COACH_DAILY_TURNS_PER_ACCOUNT = "2";
    await seedUser(t, ALICE);
    await send(t, ALICE, "one");
    await send(t, ALICE, "two");
    await expectRefusal(send(t, ALICE, "three"), "limit_reached");
    expect(modelCalls).toHaveLength(2);
  });

  test("with no model configured the Coach answers coach_unavailable and stores nothing", async () => {
    const t = convexTest(schema, modules);
    delete process.env.OPENAI_API_KEY;
    await seedUser(t, ALICE);
    await expectRefusal(send(t, ALICE, "hello"), "coach_unavailable");
    expect(modelCalls).toHaveLength(0);
    expect((await t.withIdentity(ALICE).query(api.coach.history, {})).messages).toEqual([]);
  });

  test("a failing model call is coach_unavailable, retryable, and stores nothing", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE);
    vi.stubGlobal("fetch", vi.fn(async () => new Response("{}", { status: 500 })));
    await expectRefusal(send(t, ALICE, "hello"), "coach_unavailable");
    expect((await t.withIdentity(ALICE).query(api.coach.history, {})).messages).toEqual([]);
  });

  test("the dev-only scripted model answers without a provider key", async () => {
    const t = convexTest(schema, modules);
    delete process.env.OPENAI_API_KEY;
    process.env.COACH_MODEL_STUB = "1";
    await seedUser(t, ALICE);
    const result = await send(t, ALICE, "I went for a run");
    expect(result.coach.proposals[0]).toMatchObject({ kind: "outsideActivity", activityType: "run" });
    expect(modelCalls).toHaveLength(0);

    // A tool call with no text gets a line naming what the card does, never that anything is done.
    delete process.env.COACH_MODEL_STUB;
    process.env.OPENAI_API_KEY = "sk-test-placeholder";
    nextResponse = () => modelReply("", [{ name: "change_today_length", arguments: { minutes: 15 } }]);
    expect((await send(t, ALICE, "15 minutes today")).coach.text).toBe("Confirm below to make today's session 15 minutes.");
    expect(modelCalls).toHaveLength(1);
  });

  test("a refusal from the model is stored as a calm reply", async () => {
    const t = convexTest(schema, modules);
    await seedUser(t, ALICE);
    nextResponse = () => ({ status: "completed", output: [{ type: "message", content: [{ type: "refusal", refusal: "no" }] }] });
    expect((await send(t, ALICE, "something odd")).coach.text).toContain("I can't help with that one");
  });
});
