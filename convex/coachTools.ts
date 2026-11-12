import { servedMovement } from "./coachCatalog";

/**
 * The Coach agent's tools (M4, US-CA03/US-CA04, decision 26/27, ADR-0017).
 *
 * The model may call only these seven. A call is never executed on the server: each becomes a
 * **proposal** returned to the app, which shows it as a card the user confirms; the app then applies
 * it locally through the same paths the user's own taps take (and syncs it like any other change),
 * with Undo. So the model can never act on its own, and can never reach anything outside this list:
 *
 * - There is deliberately no tool for a de-load, a Return / Re-entry Ramp, the cold start, the
 *   progression pace, the earned phase, or the injury flags. Those stay owned by the on-device engine
 *   and by the user (ADR-0005); a call naming anything else is dropped (`parseToolCalls`).
 * - A Custom Workout is a separate, user-accepted artifact, not a policy write: it can only be
 *   proposed, and nothing plays until the user accepts it in the app (FR-11).
 *
 * Every argument is checked and clamped here before it reaches the app, so a malformed or hostile
 * call becomes no proposal rather than a strange one.
 */

/** The schema the model is given for each tool (OpenAI Responses API function tools, strict mode). */
export const COACH_TOOLS = [
  {
    type: "function",
    name: "log_outside_activity",
    description:
      "Propose logging a workout the user did outside Rep Today (a run, a swim). The user confirms it in the app. " +
      "Use when the user says they already did one.",
    strict: true,
    parameters: {
      type: "object",
      additionalProperties: false,
      required: ["type", "minutes", "distance_km", "day"],
      properties: {
        type: { type: "string", enum: ["run", "bike", "hike", "swim", "row", "climb", "other"] },
        minutes: { type: "integer", description: "How long it lasted, 1 to 600." },
        distance_km: { type: ["number", "null"], description: "Distance in kilometres when the user gave one, else null." },
        day: { type: "string", enum: ["today", "yesterday"] },
      },
    },
  },
  {
    type: "function",
    name: "set_rest_choice",
    description:
      "Propose resting today instead of training (rest_today), or training today even though today is a Rest Day (train_anyway).",
    strict: true,
    parameters: {
      type: "object",
      additionalProperties: false,
      required: ["choice"],
      properties: { choice: { type: "string", enum: ["rest_today", "train_anyway"] } },
    },
  },
  {
    type: "function",
    name: "change_today_length",
    description: "Propose a different length for today's session, in minutes.",
    strict: true,
    parameters: {
      type: "object",
      additionalProperties: false,
      required: ["minutes"],
      properties: { minutes: { type: "integer", enum: [5, 10, 15, 20, 30, 45, 60] } },
    },
  },
  {
    type: "function",
    name: "swap_movement",
    description:
      "Propose swapping one movement out of today's session. Rep Today picks the closest alternative. " +
      "movement_id must be one of the ids listed in today's session.",
    strict: true,
    parameters: {
      type: "object",
      additionalProperties: false,
      required: ["movement_id"],
      properties: { movement_id: { type: "string" } },
    },
  },
  {
    type: "function",
    name: "set_focus_areas",
    description:
      "Propose the user's Focus Areas: the body parts they want to improve. Send the full new list (it replaces the old one).",
    strict: true,
    parameters: {
      type: "object",
      additionalProperties: false,
      required: ["areas"],
      properties: {
        areas: {
          type: "array",
          items: { type: "string", enum: ["chest", "shoulders", "arms", "back", "abs", "legs", "glutes"] },
        },
      },
    },
  },
  {
    type: "function",
    name: "schedule_reminder",
    description: "Propose a repeating reminder on the user's phone to train, at a time of day on chosen days.",
    strict: true,
    parameters: {
      type: "object",
      additionalProperties: false,
      required: ["time", "days"],
      properties: {
        time: { type: "string", description: "24-hour local time, HH:MM." },
        days: {
          type: "array",
          items: { type: "string", enum: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] },
        },
      },
    },
  },
  {
    type: "function",
    name: "propose_custom_workout",
    description:
      "Write a Custom Workout for the user to review, edit and accept. Bodyweight only, no equipment. " +
      "Prefer catalog movements (give their catalog_id); any other movement is allowed with catalog_id null.",
    strict: true,
    parameters: {
      type: "object",
      additionalProperties: false,
      required: ["title", "note", "steps"],
      properties: {
        title: { type: "string", description: "A short name, at most 40 characters." },
        note: { type: "string", description: "One or two sentences on what it is for." },
        steps: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: ["name", "catalog_id", "sets", "reps", "seconds", "per_side", "rest_seconds"],
            properties: {
              name: { type: "string" },
              catalog_id: { type: ["string", "null"] },
              sets: { type: "integer", description: "1 to 6." },
              reps: { type: ["integer", "null"], description: "Reps per set, or null for a timed step." },
              seconds: { type: ["integer", "null"], description: "Seconds per set for a hold or timed step, else null." },
              per_side: { type: "boolean" },
              rest_seconds: { type: "integer", description: "Rest after each set, 0 to 180." },
            },
          },
        },
      },
    },
  },
] as const;

/** The tool names the model may call; anything else is dropped. */
export const COACH_TOOL_NAMES = COACH_TOOLS.map((tool) => tool.name);

// MARK: - Proposals

export type ProposalStatus = "proposed" | "applied" | "undone" | "declined";

export type OutsideActivityType = "run" | "bike" | "hike" | "swim" | "row" | "climb" | "other";

export type CustomWorkoutStep = {
  name: string;
  exerciseId?: string;
  sets: number;
  reps?: number;
  seconds?: number;
  perSide: boolean;
  restSeconds: number;
};

export type CustomWorkoutDraft = { title: string; note: string; steps: CustomWorkoutStep[] };

/** One proposal as the app receives and stores it. */
export type CoachProposal =
  | { id: string; kind: "outsideActivity"; status: ProposalStatus; activityType: OutsideActivityType; minutes: number; distanceMeters?: number; day: "today" | "yesterday" }
  | { id: string; kind: "restChoice"; status: ProposalStatus; choice: "restToday" | "trainAnyway" }
  | { id: string; kind: "todayLength"; status: ProposalStatus; minutes: number }
  | { id: string; kind: "swapMovement"; status: ProposalStatus; exerciseId: string; exerciseName: string }
  | { id: string; kind: "focusAreas"; status: ProposalStatus; areas: string[] }
  | { id: string; kind: "reminder"; status: ProposalStatus; hour: number; minute: number; weekdays: number[] }
  | { id: string; kind: "customWorkout"; status: ProposalStatus; workout: CustomWorkoutDraft };

/** One function call the model returned. */
export type ToolCall = { name: string; arguments: string };

/** What the server knows about today's session, to check a swap against. */
export type TodayMovement = { id: string; name: string };

/** The most action proposals (not counting a Custom Workout) one turn may carry. */
export const MAX_ACTION_PROPOSALS = 3;
/** The steps a Custom Workout may hold. */
export const MAX_CUSTOM_STEPS = 12;
export const LENGTH_CHOICES = [5, 10, 15, 20, 30, 45, 60];
const FOCUS_AREAS = ["chest", "shoulders", "arms", "back", "abs", "legs", "glutes"];
const ACTIVITY_TYPES: OutsideActivityType[] = ["run", "bike", "hike", "swim", "row", "climb", "other"];
/** `Calendar` weekday numbers (1 = Sunday), the form the app schedules notifications with. */
const WEEKDAYS: Record<string, number> = { sun: 1, mon: 2, tue: 3, wed: 4, thu: 5, fri: 6, sat: 7 };

/**
 * Turns the model's tool calls into proposals: unknown tools are dropped, arguments are validated and
 * clamped, a kind proposed twice keeps its first, at most `MAX_ACTION_PROPOSALS` actions and one Custom
 * Workout survive.
 */
export function parseToolCalls(calls: ToolCall[], today: TodayMovement[], newId: () => string): CoachProposal[] {
  const proposals: CoachProposal[] = [];
  const kinds = new Set<string>();
  for (const call of calls) {
    let args: unknown;
    try {
      args = JSON.parse(call.arguments);
    } catch {
      continue;
    }
    if (args === null || typeof args !== "object" || Array.isArray(args)) continue;
    const proposal = toProposal(call.name, args as Record<string, unknown>, today, newId);
    if (proposal === null || kinds.has(proposal.kind)) continue;
    const actions = proposals.filter((existing) => existing.kind !== "customWorkout").length;
    if (proposal.kind !== "customWorkout" && actions >= MAX_ACTION_PROPOSALS) continue;
    kinds.add(proposal.kind);
    proposals.push(proposal);
  }
  return proposals;
}

function toProposal(name: string, args: Record<string, unknown>, today: TodayMovement[], newId: () => string): CoachProposal | null {
  const id = newId();
  switch (name) {
    case "log_outside_activity": {
      const activityType = ACTIVITY_TYPES.find((type) => type === args.type);
      const minutes = integer(args.minutes);
      const day = args.day === "yesterday" ? "yesterday" : args.day === "today" ? "today" : undefined;
      if (activityType === undefined || minutes === undefined || minutes < 1 || minutes > 600 || day === undefined) return null;
      const km = typeof args.distance_km === "number" && Number.isFinite(args.distance_km) && args.distance_km > 0 && args.distance_km <= 500
        ? args.distance_km
        : undefined;
      return {
        id,
        kind: "outsideActivity",
        status: "proposed",
        activityType,
        minutes,
        day,
        ...(km === undefined ? {} : { distanceMeters: Math.round(km * 1000) }),
      };
    }
    case "set_rest_choice": {
      if (args.choice === "rest_today") return { id, kind: "restChoice", status: "proposed", choice: "restToday" };
      if (args.choice === "train_anyway") return { id, kind: "restChoice", status: "proposed", choice: "trainAnyway" };
      return null;
    }
    case "change_today_length": {
      const minutes = integer(args.minutes);
      return minutes !== undefined && LENGTH_CHOICES.includes(minutes) ? { id, kind: "todayLength", status: "proposed", minutes } : null;
    }
    case "swap_movement": {
      const movement = today.find((entry) => entry.id === args.movement_id);
      return movement === undefined ? null : { id, kind: "swapMovement", status: "proposed", exerciseId: movement.id, exerciseName: movement.name };
    }
    case "set_focus_areas": {
      if (!Array.isArray(args.areas)) return null;
      const areas = FOCUS_AREAS.filter((area) => (args.areas as unknown[]).includes(area));
      return { id, kind: "focusAreas", status: "proposed", areas };
    }
    case "schedule_reminder": {
      const match = typeof args.time === "string" ? /^([01]?\d|2[0-3]):([0-5]\d)$/.exec(args.time.trim()) : null;
      if (match === null || !Array.isArray(args.days)) return null;
      const weekdays = [...new Set((args.days as unknown[]).flatMap((day) => (typeof day === "string" && day in WEEKDAYS ? [WEEKDAYS[day]] : [])))].sort((a, b) => a - b);
      if (weekdays.length === 0) return null;
      return { id, kind: "reminder", status: "proposed", hour: Number(match[1]), minute: Number(match[2]), weekdays };
    }
    case "propose_custom_workout": {
      const workout = customWorkout(args);
      return workout === null ? null : { id, kind: "customWorkout", status: "proposed", workout };
    }
    default:
      return null;
  }
}

/** Validates and clamps a Custom Workout draft; catalog ids that are not served become text-only steps. */
export function customWorkout(args: Record<string, unknown>): CustomWorkoutDraft | null {
  const title = text(args.title, 40);
  if (title === undefined || !Array.isArray(args.steps)) return null;
  const note = text(args.note, 280) ?? "";
  const steps: CustomWorkoutStep[] = [];
  for (const raw of args.steps.slice(0, MAX_CUSTOM_STEPS)) {
    if (raw === null || typeof raw !== "object") continue;
    const step = raw as Record<string, unknown>;
    const catalog = typeof step.catalog_id === "string" ? servedMovement(step.catalog_id) : undefined;
    const name = catalog?.name ?? text(step.name, 60);
    if (name === undefined) continue;
    const sets = clamp(integer(step.sets) ?? 3, 1, 6);
    const rest = clamp(integer(step.rest_seconds) ?? 30, 0, 180);
    const reps = integer(step.reps);
    const seconds = integer(step.seconds);
    // A catalog hold is timed and a catalog rep movement counts reps, whatever the model sent.
    const timed = catalog !== undefined ? catalog.isHold : seconds !== undefined && seconds > 0 && (reps === undefined || reps <= 0);
    const perSide = catalog !== undefined ? catalog.isPerSide : step.per_side === true;
    steps.push({
      name,
      ...(catalog === undefined ? {} : { exerciseId: catalog.id }),
      sets,
      ...(timed ? { seconds: clamp(seconds ?? 30, 5, 300) } : { reps: clamp(reps ?? 10, 1, 100) }),
      perSide,
      restSeconds: rest,
    });
  }
  return steps.length === 0 ? null : { title, note, steps };
}

function integer(value: unknown): number | undefined {
  return typeof value === "number" && Number.isInteger(value) ? value : undefined;
}

function clamp(value: number, low: number, high: number): number {
  return Math.min(Math.max(value, low), high);
}

function text(value: unknown, maximum: number): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.replace(/\s+/g, " ").trim();
  if (trimmed.length === 0) return undefined;
  return trimmed.length > maximum ? `${trimmed.slice(0, maximum - 1).trimEnd()}…` : trimmed;
}

/**
 * The reply stored when the model called tools but wrote no text, which models often do: one plain line
 * per kind of proposal, saying what the card below does - never that anything is done.
 */
export function proposalReply(proposals: CoachProposal[]): string {
  if (proposals.length !== 1) {
    return "I've put those below for you to confirm.";
  }
  const [proposal] = proposals;
  switch (proposal.kind) {
    case "outsideActivity":
      return "Nice work getting that in. Confirm below to log it.";
    case "restChoice":
      return proposal.choice === "restToday"
        ? "Rest is part of the plan. Confirm below to rest today."
        : "Confirm below to train today instead of resting.";
    case "todayLength":
      return `Confirm below to make today's session ${proposal.minutes} minutes.`;
    case "swapMovement":
      return `Confirm below and Rep Today will swap ${proposal.exerciseName} for the closest alternative.`;
    case "focusAreas":
      return "Confirm below to update your Focus Areas.";
    case "reminder":
      return "Confirm below to set that reminder.";
    case "customWorkout":
      return "Here's a workout for you. Look it over, change anything you like, then accept it to play.";
  }
}
