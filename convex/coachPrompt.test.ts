import { describe, expect, test } from "vitest";
import internalWords from "../proxy/coach-internal-words.json";
import { catalogMessage, COACH_INSTRUCTIONS, contextMessage } from "./coachPrompt";
import { SERVED_CATALOG } from "./coachCatalog";

/**
 * What the Coach model is told (M4): the words the app never shows a user stay out of the
 * instructions and the user summary, exactly as `proxy/test/worker.test.js` held the Worker's Coach
 * to the same list (`proxy/coach-internal-words.json`, the one list). The instructions may name a
 * listed word only in the one sentence that says what to use instead.
 */

type Listed = { word: string; forms: string[]; onlyWith?: string | null };
const WORDS = (internalWords as { words: Listed[] }).words;

function wordsIn(text: string): string[] {
  return text
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
}

function saysPhrase(text: string, phrase: string): boolean {
  const words = wordsIn(text);
  const run = wordsIn(phrase);
  return words.some((_, start) => run.every((word, offset) => words[start + offset] === word));
}

function listedWordUses(text: string): string[] {
  return text.split(/(?<=[.:;])\s+/).flatMap((sentence) =>
    WORDS.filter(
      ({ forms, onlyWith }) => forms.some((form) => saysPhrase(sentence, form)) && !(onlyWith && saysPhrase(sentence, onlyWith)),
    ).map(({ word }) => `${word}: ${sentence}`),
  );
}

const SAMPLE_CONTEXT = contextMessage({
  ageGroup: "adult",
  profile: {
    phase: "discipline",
    consistency: { score: 64, weeklyGoal: 3, totalWorkoutsCompleted: 12 },
    duration: { defaultMinutes: 20 },
    profile: { fitnessLevel: "intermediate", injuries: ["wrists"] },
  },
  focusAreas: ["back", "abs"],
  logs: [
    {
      completedAt: Date.UTC(2026, 10, 10, 15),
      durationMinutes: 20,
      perceivedDifficulty: "too_hard",
      exercises: [
        { exerciseId: "pull_floor_row", movementPattern: "pull", role: "main", skipped: false, completedSets: [{ reps: 20 }, { reps: 20 }] },
        { exerciseId: "core_dead_bug", movementPattern: "core", role: "core", skipped: true, completedSets: [] },
      ],
    },
    { completedAt: Date.UTC(2026, 10, 8, 15), durationMinutes: 8, exercises: [{ exerciseId: "mobility_cat_cow", role: "recovery", completedSets: [{ durationSeconds: 30 }] }] },
  ],
  activities: [
    { date: Date.UTC(2026, 10, 9, 15), type: "run", durationMinutes: 30, distanceMeters: 5000 },
    { date: Date.UTC(2026, 10, 9, 18), type: "other", durationMinutes: 22, customWorkoutId: "W1", customWorkoutTitle: "Desk Reset" },
  ],
  customWorkouts: [{ title: "Desk Reset", playedAt: [1] }],
  today: { localDate: "2026-11-11", utcOffsetMinutes: -480, kind: "rest", trainingDay: "legs", minutes: 20, movements: [] },
});

describe("the Coach instructions and summary use the app's own words", () => {
  test("no listed word outside the one sentence that says what to use instead", () => {
    const start = COACH_INSTRUCTIONS.indexOf("Never use these words in a reply");
    const end = COACH_INSTRUCTIONS.indexOf("Use the words the app shows the user.");
    expect(start).toBeGreaterThan(-1);
    expect(end).toBeGreaterThan(start);
    const rest = `${COACH_INSTRUCTIONS.slice(0, start)}${COACH_INSTRUCTIONS.slice(end)}`;
    expect(listedWordUses(rest)).toEqual([]);
  });

  test("the user summary names no listed word", () => {
    expect(listedWordUses(SAMPLE_CONTEXT)).toEqual([]);
  });

  test("the catalog offered for Custom Workouts names no listed word in its movement names", () => {
    expect(listedWordUses(SERVED_CATALOG.map((movement) => movement.name).join(". "))).toEqual([]);
  });
});

describe("contextMessage", () => {
  test("writes the user's records out in plain words, in the user's own time zone", () => {
    expect(SAMPLE_CONTEXT).toContain("- Age group: adult (18 or over).");
    expect(SAMPLE_CONTEXT).toContain("- They are working toward the Strength Phase.");
    expect(SAMPLE_CONTEXT).toContain("- Consistency: 64 out of 100");
    expect(SAMPLE_CONTEXT).toContain("- Injury areas they flagged: wrists.");
    expect(SAMPLE_CONTEXT).toContain("- Focus Areas: back, abs.");
    expect(SAMPLE_CONTEXT).toContain("Today is a Rest Day; the next Training Day is Legs");
    expect(SAMPLE_CONTEXT).toContain("2026-11-10: Pull Training Day, 20 min; felt too hard.");
    expect(SAMPLE_CONTEXT).toContain("Dead Bug (skipped)");
    expect(SAMPLE_CONTEXT).toContain("2026-11-08: Recovery stretches");
    expect(SAMPLE_CONTEXT).toContain('played the Custom Workout "Desk Reset", 22 min');
    expect(SAMPLE_CONTEXT).toContain("run, 30 min, 5.0 km");
    expect(SAMPLE_CONTEXT).toContain("- Desk Reset: played 1 time.");
  });

  test("an unknown age is treated as under 18", () => {
    const text = contextMessage({ ageGroup: "unknown", profile: null, focusAreas: [], logs: [], activities: [], customWorkouts: [], today: null });
    expect(text).toContain("Age group: unknown. Treat as under 18: no diet topics.");
    expect(text).toContain("- None yet.");
  });

  test("the catalog lists only served movements, with their ids", () => {
    const catalog = catalogMessage();
    expect(catalog).toContain("- push_incline: Incline Push-Up (push");
    expect(catalog).not.toContain("pull_ytw");
    expect(SERVED_CATALOG.length).toBe(68);
  });
});
