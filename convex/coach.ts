import { v, type Infer } from "convex/values";
import { action, internalMutation, internalQuery, mutation, query, type QueryCtx } from "./_generated/server";
import type { Doc } from "./_generated/dataModel";
import { internal } from "./_generated/api";
import { accountError, findAccount, requireOwner, writableAccount } from "./ownership";
import { premiumState } from "./entitlements";
import { catalogMessage, COACH_INSTRUCTIONS, contextMessage, type TodaySnapshot } from "./coachPrompt";
import { coachModelConfigured, runCoachModel, type ModelInputMessage } from "./coachModel";
import { parseToolCalls, type CoachProposal, type ProposalStatus } from "./coachTools";
import { ageGroup, DIET_DECLINE_REPLY, isDietTopic, mayDiscussDiet, replyMentionsDiet } from "./coachSafety";

/**
 * The Coach agent on Convex (M4, US-CA01/US-CA03, decisions 25-26, ADR-0017).
 *
 * A Coach turn is one Convex action, authenticated by the Clerk session token like every account
 * function (`requireOwner`). On the server it reads the user's own records - profile and injury
 * areas, sessions, Outside Activities, Custom Workouts, Focus Areas and the conversation so far -
 * checks the Premium entitlement Apple's signed data keeps (`convex/entitlements.ts`), applies the
 * diet age rail (`convex/coachSafety.ts`), asks the model once (`convex/coachModel.ts`), turns its tool
 * calls into proposals (`convex/coachTools.ts`), and stores both messages as the conversation memory.
 *
 * The public API is exactly `history`, `send` and `recordProposalOutcome`. None takes an owner id;
 * none writes the user's training records - a proposal is applied by the app, through its own
 * local-first paths, after the user confirms it.
 */

declare const process: { readonly env: Readonly<Record<string, string | undefined>> };

/** The longest message accepted. */
export const MAX_MESSAGE_LENGTH = 2000;
/** How many earlier messages the model sees. */
export const MEMORY_CONTEXT_MESSAGES = 24;
/** How many messages `history` returns. */
export const HISTORY_LIMIT = 200;
/** The default daily turn limits (per account, and for the whole deployment). */
export const DEFAULT_DAILY_TURNS_PER_ACCOUNT = 60;
export const DEFAULT_DAILY_TURNS_TOTAL = 3000;
/** The reserved `coachUsage` owner that counts every turn on the deployment. */
const ALL_OWNERS = "*";
/** How many days of turn counters are kept. */
const USAGE_RETENTION_DAYS = 3;

/** The reply stored when the model refuses a request. */
export const REFUSAL_REPLY = "I can't help with that one. Ask me about your training, a movement, or your sessions.";
/** The reply stored when the model only called tools. */
export const PROPOSAL_ONLY_REPLY = "I've put that below for you to confirm.";

/** A message as the app receives it. */
export type CoachMessage = {
  id: string;
  role: "user" | "coach";
  text: string;
  createdAt: number;
  proposals: CoachProposal[];
};

/** A message as `coachMemory.payload` stores it. */
type StoredMessage = {
  role: "user" | "coach";
  text: string;
  createdAt: number;
  /** For a coach message, the user message it answers. */
  replyTo?: string;
  proposals?: CoachProposal[];
};

const todaySnapshot = v.object({
  localDate: v.string(),
  utcOffsetMinutes: v.number(),
  kind: v.union(v.literal("train"), v.literal("rest")),
  trainingDay: v.optional(v.union(v.literal("push"), v.literal("pull"), v.literal("legs"))),
  minutes: v.number(),
  movements: v.array(v.object({ id: v.string(), name: v.string() })),
});

// MARK: - Public functions

/** The caller's conversation, oldest first: the most recent `HISTORY_LIMIT` messages. */
export const history = query({
  args: {},
  handler: async (ctx) => {
    const owner = await requireOwner(ctx);
    const account = await findAccount(ctx, owner.ownerId);
    if (account?.deletionStartedAt !== undefined) {
      throw accountError("account_deleting", "This account is being deleted.");
    }
    const rows = await recentMemory(ctx, owner.ownerId, HISTORY_LIMIT);
    return { messages: rows.map(wireMessage).filter((message): message is CoachMessage => message !== null) };
  },
});

/**
 * One Coach turn. `clientMessageId` is the app's id for the user's message (a UUID); a retry with the
 * same id returns the stored answer instead of asking the model again.
 */
export const send = action({
  args: { clientMessageId: v.string(), message: v.string(), today: v.optional(todaySnapshot) },
  handler: async (ctx, args): Promise<{ user: CoachMessage; coach: CoachMessage }> => {
    const owner = await requireOwner(ctx);
    const message = args.message.trim();
    if (!UUID_PATTERN.test(args.clientMessageId) || message.length === 0 || message.length > MAX_MESSAGE_LENGTH) {
      throw accountError("invalid_message", `A message is 1 to ${MAX_MESSAGE_LENGTH} characters with a valid id.`);
    }
    const today = args.today === undefined ? null : validToday(args.today);
    const now = Date.now();
    const turn = await ctx.runQuery(internal.coach.turnContext, { ownerId: owner.ownerId, clientMessageId: args.clientMessageId.toLowerCase(), now });
    if (turn.deleting) {
      throw accountError("account_deleting", "This account is being deleted.");
    }
    if (turn.existing !== null) {
      return turn.existing;
    }
    // The entitlement is decided here, on the server, on every turn - never from the app.
    if (!turn.premium) {
      throw accountError("not_premium", "The Coach is part of Premium.");
    }
    if (turn.turnsToday >= dailyLimit("COACH_DAILY_TURNS_PER_ACCOUNT", DEFAULT_DAILY_TURNS_PER_ACCOUNT) ||
        turn.turnsTodayTotal >= dailyLimit("COACH_DAILY_TURNS_TOTAL", DEFAULT_DAILY_TURNS_TOTAL)) {
      throw accountError("limit_reached", "The Coach has answered a lot today. Try again tomorrow.");
    }

    const group = ageGroup(turn.age);
    let reply: string;
    let proposals: CoachProposal[] = [];
    if (!mayDiscussDiet(group) && isDietTopic(message)) {
      // FR-12: a diet question from someone not known to be an adult never reaches the model.
      reply = DIET_DECLINE_REPLY;
    } else {
      if (!coachModelConfigured()) {
        throw accountError("coach_unavailable", "The Coach is not configured on this deployment.");
      }
      const context = contextMessage({
        ageGroup: group,
        profile: turn.profile,
        focusAreas: turn.focusAreas,
        logs: turn.logs,
        activities: turn.activities,
        customWorkouts: turn.customWorkouts,
        today,
      });
      const input: ModelInputMessage[] = [
        { role: "developer", content: `${context}\n\n${catalogMessage()}` },
        ...turn.memory.map(memoryInput),
        { role: "user", content: message },
      ];
      const outcome = await runCoachModel({
        instructions: COACH_INSTRUCTIONS,
        input,
        safetyIdentifier: await safetyIdentifier(owner.ownerId),
      });
      if (outcome.kind === "unavailable") {
        throw accountError("coach_unavailable", "The Coach couldn't answer just now.");
      }
      if (outcome.kind === "refusal") {
        reply = REFUSAL_REPLY;
      } else {
        proposals = parseToolCalls(outcome.toolCalls, today?.movements ?? [], () => crypto.randomUUID().toLowerCase());
        reply = outcome.text.length > 0 ? outcome.text : proposals.length > 0 ? PROPOSAL_ONLY_REPLY : "";
        if (reply.length === 0) {
          throw accountError("coach_unavailable", "The Coach couldn't answer just now.");
        }
        if (!mayDiscussDiet(group) && replyMentionsDiet(reply)) {
          // The same rail, after the model: a reply that drifted into diet is never shown.
          reply = DIET_DECLINE_REPLY;
        }
      }
    }

    return await ctx.runMutation(internal.coach.recordTurn, {
      ownerId: owner.ownerId,
      clerkUserId: owner.clerkUserId,
      clientMessageId: args.clientMessageId.toLowerCase(),
      message,
      reply,
      proposals: JSON.stringify(proposals),
      day: utcDay(now),
    });
  },
});

/** The allowed changes to a proposal's status: confirm or decline it once, and undo what was applied. */
const TRANSITIONS: Record<ProposalStatus, ProposalStatus[]> = {
  proposed: ["applied", "declined"],
  applied: ["undone"],
  undone: [],
  declined: [],
};

/**
 * Records what the user did with a proposal, so the conversation (and the model, next turn) knows
 * whether it was applied, declined or undone. The app has already applied or reverted the change
 * itself; this writes only the conversation memory.
 */
export const recordProposalOutcome = mutation({
  args: {
    messageId: v.string(),
    proposalId: v.string(),
    status: v.union(v.literal("applied"), v.literal("undone"), v.literal("declined")),
  },
  handler: async (ctx, { messageId, proposalId, status }) => {
    const owner = await requireOwner(ctx);
    await writableAccount(ctx, owner);
    const row = await ctx.db
      .query("coachMemory")
      .withIndex("by_ownerId_recordId", (q) => q.eq("ownerId", owner.ownerId).eq("recordId", messageId.toLowerCase()))
      .unique();
    const stored = row === null ? null : storedMessage(row);
    const proposal = stored?.proposals?.find((candidate) => candidate.id === proposalId.toLowerCase());
    if (row === null || stored === null || proposal === undefined) {
      throw accountError("invalid_change", "No such proposal.");
    }
    if (proposal.status === status) {
      return { status };
    }
    if (!TRANSITIONS[proposal.status].includes(status)) {
      throw accountError("invalid_change", `A ${proposal.status} proposal cannot become ${status}.`);
    }
    proposal.status = status;
    await ctx.db.patch(row._id, { payload: JSON.stringify(stored), clientUpdatedAt: Date.now() });
    return { status };
  },
});

// MARK: - Internal functions

/** Everything one turn reads, in one consistent snapshot. */
export const turnContext = internalQuery({
  args: { ownerId: v.string(), clientMessageId: v.string(), now: v.number() },
  handler: async (ctx, { ownerId, clientMessageId, now }) => {
    const account = await findAccount(ctx, ownerId);
    const deleting = account?.deletionStartedAt !== undefined;
    const existing = await existingTurn(ctx, ownerId, clientMessageId);
    const profileRow = await ctx.db
      .query("profiles")
      .withIndex("by_ownerId", (q) => q.eq("ownerId", ownerId))
      .unique();
    const profile = parsePayload(profileRow?.payload);
    const focus = await ctx.db
      .query("focusAreas")
      .withIndex("by_ownerId", (q) => q.eq("ownerId", ownerId))
      .unique();
    const day = utcDay(now);
    const usage = async (owner: string) =>
      (await ctx.db
        .query("coachUsage")
        .withIndex("by_ownerId_day", (q) => q.eq("ownerId", owner).eq("day", day))
        .unique())?.count ?? 0;
    const memoryRows = await recentMemory(ctx, ownerId, MEMORY_CONTEXT_MESSAGES);
    return {
      deleting,
      existing,
      premium: (await premiumState(ctx, ownerId, now)).premium,
      age: (profile?.profile as Record<string, unknown> | undefined)?.age ?? null,
      profile,
      focusAreas: focus?.areas ?? [],
      logs: newest(await liveRows(ctx, "workoutLogs", ownerId, 60), "completedAt", 14),
      activities: newest(await liveRows(ctx, "outsideActivities", ownerId, 40), "date", 10),
      customWorkouts: (await liveRows(ctx, "customWorkouts", ownerId, 20)).filter((workout) => typeof workout.acceptedAt === "number").slice(-5).reverse(),
      memory: memoryRows.map(storedMessage).filter((message): message is StoredMessage => message !== null),
      turnsToday: await usage(ownerId),
      turnsTodayTotal: await usage(ALL_OWNERS),
    };
  },
});

/** Stores one turn - the user's message and the Coach's reply - and counts it. */
export const recordTurn = internalMutation({
  args: {
    ownerId: v.string(),
    clerkUserId: v.string(),
    clientMessageId: v.string(),
    message: v.string(),
    reply: v.string(),
    proposals: v.string(),
    day: v.string(),
  },
  handler: async (ctx, args): Promise<{ user: CoachMessage; coach: CoachMessage }> => {
    const account = await writableAccount(ctx, { ownerId: args.ownerId, clerkUserId: args.clerkUserId });
    const replay = await existingTurn(ctx, args.ownerId, args.clientMessageId);
    if (replay !== null) {
      return replay;
    }
    const now = Date.now();
    const proposals = JSON.parse(args.proposals) as CoachProposal[];
    const coachId = crypto.randomUUID().toLowerCase();
    let seq = account.changeSeq;
    const user: StoredMessage = { role: "user", text: args.message, createdAt: now };
    const coach: StoredMessage = { role: "coach", text: args.reply, createdAt: now + 1, replyTo: args.clientMessageId, proposals };
    for (const [recordId, stored] of [
      [args.clientMessageId, user],
      [coachId, coach],
    ] as const) {
      await ctx.db.insert("coachMemory", {
        ownerId: args.ownerId,
        recordId,
        serverSeq: ++seq,
        clientUpdatedAt: stored.createdAt,
        payload: JSON.stringify(stored),
        deleted: false,
      });
    }
    await ctx.db.patch(account._id, { changeSeq: seq });
    for (const owner of [args.ownerId, ALL_OWNERS]) {
      const usage = await ctx.db
        .query("coachUsage")
        .withIndex("by_ownerId_day", (q) => q.eq("ownerId", owner).eq("day", args.day))
        .unique();
      if (usage === null) {
        await ctx.db.insert("coachUsage", { ownerId: owner, day: args.day, count: 1 });
      } else {
        await ctx.db.patch(usage._id, { count: usage.count + 1 });
      }
    }
    return {
      user: { id: args.clientMessageId, role: "user", text: user.text, createdAt: user.createdAt, proposals: [] },
      coach: { id: coachId, role: "coach", text: coach.text, createdAt: coach.createdAt, proposals },
    };
  },
});

/** Sweeps turn counters older than the retention window. */
export const reclaimUsage = internalMutation({
  args: {},
  handler: async (ctx) => {
    const cutoff = utcDay(Date.now() - USAGE_RETENTION_DAYS * 24 * 60 * 60 * 1000);
    const old = await ctx.db
      .query("coachUsage")
      .withIndex("by_day", (q) => q.lt("day", cutoff))
      .take(500);
    for (const row of old) {
      await ctx.db.delete(row._id);
    }
    return old.length;
  },
});

// MARK: - Helpers

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type TodayArg = Infer<typeof todaySnapshot>;

/** Today's plan as the app sent it, bounded; a malformed one is ignored rather than refused. */
function validToday(today: TodayArg): TodaySnapshot | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(today.localDate) || !Number.isFinite(today.utcOffsetMinutes) || Math.abs(today.utcOffsetMinutes) > 14 * 60) {
    return null;
  }
  if (!Number.isFinite(today.minutes) || today.minutes < 1 || today.minutes > 120 || today.movements.length > 16) {
    return null;
  }
  const movements = today.movements
    .filter((movement) => /^[a-z0-9_]{1,64}$/.test(movement.id) && movement.name.length > 0 && movement.name.length <= 80)
    .map((movement) => ({ id: movement.id, name: movement.name.trim() }));
  return {
    localDate: today.localDate,
    utcOffsetMinutes: Math.round(today.utcOffsetMinutes),
    kind: today.kind,
    ...(today.trainingDay === undefined ? {} : { trainingDay: today.trainingDay }),
    minutes: Math.round(today.minutes),
    movements,
  };
}

function dailyLimit(name: string, fallback: number): number {
  const configured = Number(process.env[name]);
  return Number.isFinite(configured) && configured > 0 ? configured : fallback;
}

function utcDay(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/** A one-way, stable id for the account, for the provider's abuse monitoring. Never the account id itself. */
export async function safetyIdentifier(ownerId: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`reptoday-coach:${ownerId}`)));
  return `rt-${Array.from(digest.slice(0, 16), (byte) => byte.toString(16).padStart(2, "0")).join("")}`;
}

async function recentMemory(ctx: QueryCtx, ownerId: string, limit: number): Promise<Doc<"coachMemory">[]> {
  const rows = await ctx.db
    .query("coachMemory")
    .withIndex("by_ownerId_serverSeq", (q) => q.eq("ownerId", ownerId))
    .order("desc")
    .take(limit);
  return rows.filter((row) => !row.deleted).reverse();
}

async function existingTurn(ctx: QueryCtx, ownerId: string, clientMessageId: string): Promise<{ user: CoachMessage; coach: CoachMessage } | null> {
  const userRow = await ctx.db
    .query("coachMemory")
    .withIndex("by_ownerId_recordId", (q) => q.eq("ownerId", ownerId).eq("recordId", clientMessageId))
    .unique();
  if (userRow === null) {
    return null;
  }
  const following = await ctx.db
    .query("coachMemory")
    .withIndex("by_ownerId_serverSeq", (q) => q.eq("ownerId", ownerId).gt("serverSeq", userRow.serverSeq))
    .take(1);
  const user = wireMessage(userRow);
  const coach = following.length === 1 && storedMessage(following[0])?.replyTo === clientMessageId ? wireMessage(following[0]) : null;
  return user === null || coach === null ? null : { user, coach };
}

function storedMessage(row: Doc<"coachMemory">): StoredMessage | null {
  const payload = parsePayload(row.payload);
  if (payload === null || (payload.role !== "user" && payload.role !== "coach") || typeof payload.text !== "string") {
    return null;
  }
  return payload as unknown as StoredMessage;
}

function wireMessage(row: Doc<"coachMemory">): CoachMessage | null {
  const stored = storedMessage(row);
  if (stored === null) return null;
  return { id: row.recordId, role: stored.role, text: stored.text, createdAt: stored.createdAt, proposals: stored.proposals ?? [] };
}

/** An earlier message as the model sees it: a coach message says what became of its proposals. */
function memoryInput(message: StoredMessage): ModelInputMessage {
  if (message.role === "user") {
    return { role: "user", content: message.text };
  }
  const notes = (message.proposals ?? []).map((proposal) => `[${describeProposal(proposal)} - ${outcomeWords(proposal.status)}]`);
  return { role: "assistant", content: [message.text, ...notes].join("\n") };
}

function outcomeWords(status: ProposalStatus): string {
  switch (status) {
    case "proposed":
      return "not answered by the user";
    case "applied":
      return "the user applied it";
    case "undone":
      return "the user applied it, then undid it";
    case "declined":
      return "the user declined it";
  }
}

function describeProposal(proposal: CoachProposal): string {
  switch (proposal.kind) {
    case "outsideActivity":
      return `Proposed logging a ${proposal.minutes}-minute ${proposal.activityType} (${proposal.day})`;
    case "restChoice":
      return proposal.choice === "restToday" ? "Proposed resting today" : "Proposed training today instead of resting";
    case "todayLength":
      return `Proposed a ${proposal.minutes}-minute session today`;
    case "swapMovement":
      return `Proposed swapping ${proposal.exerciseName} out of today's session`;
    case "focusAreas":
      return proposal.areas.length > 0 ? `Proposed Focus Areas: ${proposal.areas.join(", ")}` : "Proposed clearing the Focus Areas";
    case "reminder":
      return `Proposed a reminder at ${String(proposal.hour).padStart(2, "0")}:${String(proposal.minute).padStart(2, "0")}`;
    case "customWorkout":
      return `Proposed the Custom Workout "${proposal.workout.title}" (${proposal.workout.steps.map((step) => step.name).join(", ")})`;
  }
}

function parsePayload(payload: string | undefined): Record<string, unknown> | null {
  if (payload === undefined) return null;
  try {
    const value: unknown = JSON.parse(payload);
    return value !== null && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

/** The owner's newest live (not deleted) rows in a record table, parsed, oldest of them first. */
async function liveRows(
  ctx: QueryCtx,
  table: "workoutLogs" | "outsideActivities" | "customWorkouts",
  ownerId: string,
  count: number,
): Promise<Record<string, unknown>[]> {
  const rows = await ctx.db
    .query(table)
    .withIndex("by_ownerId_serverSeq", (q) => q.eq("ownerId", ownerId))
    .order("desc")
    .take(count);
  return rows
    .filter((row) => !row.deleted)
    .map((row) => parsePayload(row.payload))
    .filter((payload): payload is Record<string, unknown> => payload !== null)
    .reverse();
}

/** The `count` records with the latest `field` (a timestamp), newest first. */
function newest(records: Record<string, unknown>[], field: string, count: number): Record<string, unknown>[] {
  const time = (record: Record<string, unknown>) => (typeof record[field] === "number" ? (record[field] as number) : 0);
  return [...records].sort((a, b) => time(b) - time(a)).slice(0, count);
}
