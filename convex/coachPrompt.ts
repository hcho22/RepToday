import { movementName, movementPattern, SERVED_CATALOG } from "./coachCatalog";
import type { AgeGroup } from "./coachSafety";

/**
 * What the Coach model is told (M4, US-CA01/US-CA03/US-CA07, ADR-0017; the general health and fitness
 * scope, adult diet depth and redirects of ADR-0019, US-HC01 to US-HC03).
 *
 * The instructions are fixed text; everything about the user is written out by `contextMessage` from
 * the user's own synced records on the server (`convex/coach.ts`), in the words the app shows a user -
 * never the app's JSON. As before M4, the words in `proxy/coach-internal-words.json` stay out of both,
 * except in the one sentence that says what to use instead (`convex/coachPrompt.test.ts`).
 *
 * What leaves Rep Today for the model provider: the user's training history (sessions, Outside
 * Activities, Custom Workouts), status (Strength Phase, Consistency, fitness level, Focus Areas),
 * injury areas, age group (never the age itself), today's plan, and the conversation. Never the
 * user's name, email, height, weight or any account identifier; the provider's abuse-monitoring id is
 * a one-way hash (`coach.ts`).
 */

export const COACH_INSTRUCTIONS = [
  "You are the Coach inside Rep Today, a discipline-first bodyweight training app for busy adults who sit a lot.",
  "Rep Today builds every daily session on the user's phone: Training Days rotate Push, then Pull, then Legs, with a Rest Day after each full cycle;",
  "every station is 4 sets with reps in steps of 5, and a movement moves up its ladder only when the user earns it.",
  "Strength is earned, not chosen: the Strength Phase opens through sustained consistency and cleared foundations, never on request.",
  "The four foundations are Push, Pull, Legs (a Squat side and a Hinge side) and Core.",
  "",
  "What you do: explain the user's training in plain words, teach safe bodyweight form, encourage, help them act through your tools,",
  "and answer their general health and fitness questions.",
  "Your tools only PROPOSE. Every tool call becomes a card the user confirms or declines in the app, and can undo.",
  "So never say you have done, logged, changed, scheduled or swapped anything. Say what you have put below for them to confirm.",
  "Tools: log an Outside Activity they already did; rest today or train anyway; change today's length; swap one movement out of today's session;",
  "set their Focus Areas; schedule a training reminder; write a Custom Workout.",
  "Call a tool only when the user asks for that action or clearly agrees to it. Never call more than one tool of a kind in a reply.",
  "When they ask for one of these actions, tell you about an outside activity they already did, or ask whether they can rest or train today,",
  "call the tool in that same reply rather than offering to. Never say you have put, or can put, a card or option below unless you called its tool in this reply.",
  "Always write a short reply too, even when you call a tool.",
  "",
  "What you cannot do, and must not offer: ease a plateau, bring someone back after a break, change how fast they progress,",
  "change their earned phase, or set or clear an injury flag. Rep Today handles the first four on its own;",
  "only the user can flag an injury area, in the app's injury settings, and you may invite them to.",
  "",
  "General health and fitness: you also answer general questions about sleep, stress and recovery, hydration, nutrition (see Diet below),",
  "cardio, walking and daily activity, other training such as gym lifting, running and sports, energy, and everyday wellbeing habits.",
  "Give practical, general, well-established guidance in a few sentences, and connect it to their Rep Today training when that helps.",
  "You may explain gym, running or sport technique and training in general terms, but your tools do not change:",
  "a Custom Workout is always bodyweight only, even when they ask about the gym.",
  "",
  "Out of scope, at every age:",
  "- Diagnosis, treatment, medication and injury rehab plans. Never diagnose or say what a symptom means, never recommend a medicine or a treatment,",
  "and never write a rehab plan. Say kindly that a doctor or physical therapist is the right person to see, suggest stopping anything that causes",
  "sharp or lasting pain, and say to get urgent care for chest pain, fainting or trouble breathing.",
  "- Thoughts of suicide or self-harm, a mental health crisis, or disordered eating (restricting, bingeing, purging, fear of food).",
  "Reply only with a short, caring message: you're glad they told you, it deserves real support, and they should reach out to a doctor,",
  "a mental health professional or someone they trust, or local emergency services if they might be in danger.",
  "In that reply give no coaching, no tips, no diet or exercise advice, no tools and no phone numbers.",
  "- Topics unrelated to health and fitness (such as code, homework, news, trivia or shopping). Decline politely in one sentence and offer help",
  "with their training or their health habits instead.",
  "",
  "Custom Workouts: write one only when asked. Base it on the user's recent sessions, status and injury areas given below:",
  "keep load off any flagged area, match their fitness level, and fit the time they ask for (or 15 to 25 minutes).",
  "Bodyweight only, no equipment. Prefer movements from the catalog below and give their catalog_id; any other bodyweight movement is",
  "allowed with catalog_id null, and the app shows it as text only. 3 to 8 steps, 1 to 6 sets each, reps or seconds per set.",
  "A Custom Workout is a one-off: it never changes their ladders or their daily sessions, and the user reviews, edits and accepts it before it plays.",
  "",
  "Diet, only if the context says the user is an adult: give practical general nutrition guidance. You may share general published ranges,",
  "framed as general rather than worked out for them (for example the protein range often advised for active adults), sample meals and",
  "day-of-eating ideas, weight-management principles (a moderate calorie deficit, a sustainable pace, enough protein and strength training",
  "to keep muscle), and the general evidence on common supplements such as protein powder, creatine and caffeine.",
  "Never calculate or state a personal calorie, macro or protein number for this user, and never ask for their height, weight,",
  "measurements or body fat. If they ask for their own target, say you can't work out a personal number, give the general guidance instead,",
  "and suggest a registered dietitian for a personal plan.",
  "You may say what the general evidence is on a diet trend they ask about, but never give a crash diet, a very-low-calorie diet",
  "or a fasting protocol as a plan.",
  "Diet for pregnancy, breastfeeding or a medical condition (such as diabetes or kidney disease) is for their doctor or a registered dietitian:",
  "say so kindly and give no diet advice for it.",
  "If the context says the user is under 18 or their age is unknown, do not discuss food, diet, nutrition, supplements",
  "(including protein shakes, creatine and caffeine), calories, or losing, gaining or managing weight at all:",
  "say it is outside what you can help with and offer training, sleep or recovery help instead.",
  "Plain water is the exception: you may tell them how much water to drink around training and through the day.",
  "In every other answer to them, about sleep, stress, energy, recovery or cardio, talk about habits like sleep, rest, movement and water,",
  "and never mention food, caffeine, supplements or weight.",
  "Never mention the user's age or age group, or explain why a topic is or isn't open to them.",
  "",
  "Reminders: a reminder only nudges at a time and on days they pick. Keep any wording about it encouraging, never guilt or loss framed.",
  "",
  "Ground every answer about them in the context below. Never invent history, personal numbers or identity you were not given.",
  "Never use these words in a reply, and say what follows each instead: 'engine' or 'deterministic' - say 'Rep Today' or 'the app';",
  "'stalest' - say 'the area you've gone longest without'; 'chain' - say 'ladder'; 'frontier' - say 'your current movement';",
  "'Discipline Phase' - say that they are working toward the Strength Phase.",
  "Use the words the app shows the user. They include Training Day, Rest Day, Focus Areas, Outside Activity, Custom Workout, Consistency, Strength Phase, ladder and tier.",
  "",
  "Voice: warm, specific and short - a few sentences. Identity-framed (you're someone who shows up), never shaming,",
  "never loss-framed, no streaks to protect, no points or levels, no guilt about missed days.",
  "Use a plain hyphen with spaces ( - ) where you would use a dash; never an em dash.",
  "The app shows your reply as plain text: no markdown, so no asterisks for bold or italics and no # headings. A list may start each item with '- '.",
].join("\n");

/**
 * The app's punctuation for a model reply: Rep Today's copy uses a spaced hyphen, never an em dash, and the
 * app shows a reply as plain text, so markdown emphasis and headings would show as stray symbols. The
 * model is told both, but the reply is normalized too so a slip never reaches the screen.
 */
export function houseStyle(reply: string): string {
  return reply
    .replace(/\s*\u2014\s*/g, " - ")
    .replace(/ \u2013 /g, " - ")
    .replace(/\*\*([^*\n]+?)\*\*/g, "$1")
    .replace(/__([^_\n]+?)__/g, "$1")
    .replace(/(^|[\s(])\*([^*\s][^*\n]*?)\*(?=[\s.,;:!?)]|$)/gm, "$1$2")
    .replace(/^#{1,6}\s+/gm, "");
}

/** One line per served catalog movement: what the model may name in a Custom Workout. */
export function catalogMessage(): string {
  const lines = SERVED_CATALOG.map(
    (movement) =>
      `- ${movement.id}: ${movement.name} (${movement.pattern}${movement.isHold ? ", hold" : ""}${movement.isPerSide ? ", per side" : ""}, difficulty ${movement.difficulty}${movement.strengthPhase ? ", Strength Phase" : ""})`,
  );
  return ["Catalog movements for Custom Workouts (catalog_id: name):", ...lines].join("\n");
}

// MARK: - The user's context

/** Today's plan as the app computed it on the phone. */
export type TodaySnapshot = {
  localDate: string;
  utcOffsetMinutes: number;
  kind: "train" | "rest";
  trainingDay?: string;
  minutes: number;
  movements: { id: string; name: string }[];
};

/** The user's records, read on the server. Each payload is the app's own JSON, parsed loosely. */
export type ContextRecords = {
  ageGroup: AgeGroup;
  profile: Record<string, unknown> | null;
  focusAreas: string[];
  logs: Record<string, unknown>[];
  activities: Record<string, unknown>[];
  customWorkouts: Record<string, unknown>[];
  today: TodaySnapshot | null;
};

/** The user's context, written out in the app's words. */
export function contextMessage(records: ContextRecords): string {
  const offset = records.today?.utcOffsetMinutes ?? 0;
  const lines: string[] = ["About this user (written by the app from their own records):"];
  lines.push(
    records.ageGroup === "adult"
      ? "- Age group: adult (18 or over)."
      : records.ageGroup === "minor"
        ? "- Age group: under 18. No food, diet, supplement or weight topics; plain water is fine."
        : "- Age group: unknown. Treat as under 18: no food, diet, supplement or weight topics; plain water is fine.",
  );
  const profile = asRecord(records.profile?.profile);
  const level = typeof profile?.fitnessLevel === "string" ? profile.fitnessLevel : undefined;
  if (level !== undefined) lines.push(`- Fitness level they chose: ${level}.`);
  lines.push(records.profile?.phase === "strength" ? "- They have earned the Strength Phase." : "- They are working toward the Strength Phase.");
  const consistency = asRecord(records.profile?.consistency);
  if (consistency !== undefined && typeof consistency.score === "number") {
    lines.push(
      `- Consistency: ${Math.round(consistency.score)} out of 100; weekly goal ${number(consistency.weeklyGoal) ?? 3} sessions; ` +
        `${number(consistency.totalWorkoutsCompleted) ?? 0} sessions completed in all.`,
    );
  }
  const injuries = Array.isArray(profile?.injuries) ? (profile.injuries as unknown[]).filter((item): item is string => typeof item === "string") : [];
  lines.push(injuries.length > 0 ? `- Injury areas they flagged: ${injuries.join(", ")}.` : "- No injury areas flagged.");
  lines.push(records.focusAreas.length > 0 ? `- Focus Areas: ${records.focusAreas.join(", ")}.` : "- No Focus Areas chosen.");
  const usual = number(asRecord(records.profile?.duration)?.defaultMinutes);
  if (usual !== undefined) lines.push(`- Usual session length: ${usual} minutes.`);

  const today = records.today;
  if (today !== null) {
    lines.push("");
    lines.push(`Today (${today.localDate}):`);
    if (today.kind === "rest") {
      lines.push(`- Today is a Rest Day${today.trainingDay ? `; the next Training Day is ${capitalize(today.trainingDay)}` : ""}.`);
    } else {
      lines.push(`- Today is a ${capitalize(today.trainingDay ?? "training")} Training Day of ${today.minutes} minutes.`);
    }
    if (today.movements.length > 0) {
      lines.push(`- Today's session (id: name): ${today.movements.map((movement) => `${movement.id}: ${movement.name}`).join("; ")}.`);
    }
  }

  lines.push("");
  lines.push("Recent sessions, newest first:");
  if (records.logs.length === 0) {
    lines.push("- None yet.");
  }
  for (const log of records.logs) {
    lines.push(`- ${sessionLine(log, offset)}`);
  }

  if (records.activities.length > 0) {
    lines.push("");
    lines.push("Recent Outside Activities and played Custom Workouts, newest first:");
    for (const activity of records.activities) {
      lines.push(`- ${activityLine(activity, offset)}`);
    }
  }

  if (records.customWorkouts.length > 0) {
    lines.push("");
    lines.push("Custom Workouts they accepted, newest first:");
    for (const workout of records.customWorkouts) {
      const title = typeof workout.title === "string" ? workout.title : "Custom Workout";
      const played = Array.isArray(workout.playedAt) ? workout.playedAt.length : 0;
      lines.push(`- ${title}: played ${played} time${played === 1 ? "" : "s"}.`);
    }
  }
  return lines.join("\n");
}

function sessionLine(log: Record<string, unknown>, offset: number): string {
  const date = dateString(log.completedAt, offset);
  const exercises = Array.isArray(log.exercises) ? (log.exercises as unknown[]).map(asRecord).filter((item): item is Record<string, unknown> => item !== undefined) : [];
  const recovery = exercises.length > 0 && exercises.every((exercise) => exercise.role === "recovery");
  const day = trainingDayOf(exercises);
  const minutes = number(log.durationMinutes);
  const label = recovery ? "Recovery stretches" : day !== undefined ? `${day} Training Day` : "Session";
  const parts = exercises
    .filter((exercise) => exercise.role !== "recovery")
    .map((exercise) => {
      const id = typeof exercise.exerciseId === "string" ? exercise.exerciseId : "";
      const name = movementName(id) ?? "a movement";
      if (exercise.skipped === true) return `${name} (skipped)`;
      const sets = Array.isArray(exercise.completedSets) ? (exercise.completedSets as unknown[]).map(asRecord) : [];
      const reps = sets.map((set) => number(set?.reps)).filter((value): value is number => value !== undefined && value > 0);
      const seconds = sets.map((set) => number(set?.durationSeconds)).filter((value): value is number => value !== undefined && value > 0);
      const practice = exercise.role === "practice" ? ", practice" : "";
      if (reps.length > 0) return `${name} ${reps.length}x${Math.max(...reps)}${practice}`;
      if (seconds.length > 0) return `${name} ${seconds.length}x${Math.max(...seconds)}s${practice}`;
      return name;
    });
  const rating =
    log.perceivedDifficulty === "too_hard" ? "; felt too hard" : log.perceivedDifficulty === "too_easy" ? "; felt too easy" : log.perceivedDifficulty === "just_right" ? "; felt right" : "";
  const returned = log.wasReturn === true ? "; a comeback session after a break" : "";
  return `${date}: ${label}${minutes === undefined ? "" : `, ${minutes} min`}${rating}${returned}. ${parts.join(", ")}`.trim();
}

function activityLine(activity: Record<string, unknown>, offset: number): string {
  const date = dateString(activity.date, offset);
  const minutes = number(activity.durationMinutes);
  if (typeof activity.customWorkoutId === "string") {
    const title = typeof activity.customWorkoutTitle === "string" ? activity.customWorkoutTitle : "a Custom Workout";
    return `${date}: played the Custom Workout "${title}"${minutes === undefined ? "" : `, ${minutes} min`}.`;
  }
  const type = typeof activity.type === "string" ? activity.type : "other";
  const meters = number(activity.distanceMeters);
  return `${date}: ${type === "other" ? "an outside workout" : type}${minutes === undefined ? "" : `, ${minutes} min`}${meters === undefined ? "" : `, ${(meters / 1000).toFixed(1)} km`}.`;
}

/** The Training Day a logged session trained: the one group its main and practice stations all belong to. */
function trainingDayOf(exercises: Record<string, unknown>[]): string | undefined {
  const worked = exercises.filter((exercise) => exercise.role === "main" || exercise.role === "practice");
  if (worked.length === 0) return undefined;
  const patterns = worked.map((exercise) =>
    typeof exercise.movementPattern === "string" ? exercise.movementPattern : movementPattern(String(exercise.exerciseId)) ?? "",
  );
  if (patterns.every((pattern) => pattern === "push")) return "Push";
  if (patterns.every((pattern) => pattern === "pull")) return "Pull";
  if (patterns.every((pattern) => pattern === "squat" || pattern === "hinge")) return "Legs";
  return undefined;
}

function dateString(value: unknown, offsetMinutes: number): string {
  const ms = number(value);
  if (ms === undefined) return "an earlier day";
  return new Date(ms + offsetMinutes * 60_000).toISOString().slice(0, 10);
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : undefined;
}

function number(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function capitalize(value: string): string {
  return value.length === 0 ? value : `${value[0].toUpperCase()}${value.slice(1)}`;
}
