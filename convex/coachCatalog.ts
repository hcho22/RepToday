import exercises from "../ios/RepToday/RepToday/Resources/Exercises.json";

/**
 * The movement catalog the Coach writes Custom Workouts from (M4, US-CA04).
 *
 * It is read straight from the app's own catalog (`Resources/Exercises.json`), which the bundler
 * folds into the deployed function, so the movements the model may name and the ids the app resolves
 * to Trainer art can never drift apart. Only served movements are offered: a movement withdrawn to
 * a later version or retired (`audience` `version2`/`retired`, ADR-0007/ADR-0014) never appears.
 */

/** A fitness level, as the app's profile records it. */
export type FitnessLevel = "beginner" | "intermediate" | "advanced";

/**
 * A movement's Fixed Target (ADR-0022): the one per-set number each fitness level is served, in seconds
 * for a hold and reps (or reps per side) otherwise. The app's catalog validation guarantees all three.
 */
export type FixedTarget = {
  unit: "seconds" | "reps" | "repsPerSide";
  beginner: number;
  intermediate: number;
  advanced: number;
};

export type CatalogMovement = {
  id: string;
  name: string;
  pattern: string;
  difficulty: number;
  isHold: boolean;
  isPerSide: boolean;
  /** Earned only in the Strength Phase. */
  strengthPhase: boolean;
  /** Set for a movement served at a Fixed Target. */
  fixedTarget?: FixedTarget;
};

type RawExercise = {
  id: string;
  displayName: string;
  movementPattern: string;
  difficulty: number;
  audience: string;
  isHold: boolean;
  isPerSide?: boolean;
  phase: string;
  fixedTarget?: FixedTarget;
};

export const SERVED_CATALOG: readonly CatalogMovement[] = (exercises as RawExercise[])
  .filter((exercise) => exercise.audience !== "version2" && exercise.audience !== "retired")
  .map((exercise) => ({
    id: exercise.id,
    name: exercise.displayName,
    pattern: exercise.movementPattern,
    difficulty: exercise.difficulty,
    isHold: exercise.isHold,
    isPerSide: exercise.isPerSide === true,
    strengthPhase: exercise.phase === "strength",
    ...(exercise.fixedTarget === undefined ? {} : { fixedTarget: exercise.fixedTarget }),
  }));

const BY_ID = new Map(SERVED_CATALOG.map((movement) => [movement.id, movement]));
const ALL_BY_ID = new Map((exercises as RawExercise[]).map((exercise) => [exercise.id, exercise]));

/** A served catalog movement by id, or `undefined`. */
export function servedMovement(id: string): CatalogMovement | undefined {
  return BY_ID.get(id);
}

/** Any catalog movement's display name, served or not (for reading history). */
export function movementName(id: string): string | undefined {
  return ALL_BY_ID.get(id)?.displayName;
}

/** Any catalog movement's pattern, served or not. */
export function movementPattern(id: string): string | undefined {
  return ALL_BY_ID.get(id)?.movementPattern;
}

/** `value` as a fitness level, or `undefined`. */
export function fitnessLevel(value: unknown): FitnessLevel | undefined {
  return value === "beginner" || value === "intermediate" || value === "advanced" ? value : undefined;
}

/** A Fixed Target's number for `level` in the app's words: "1:00 per hold", "15 per side", "20 reps". */
export function fixedTargetText(target: FixedTarget, level: FitnessLevel): string {
  const value = target[level];
  switch (target.unit) {
    case "seconds":
      return `${Math.floor(value / 60)}:${String(value % 60).padStart(2, "0")} per hold`;
    case "repsPerSide":
      return `${value} per side`;
    case "reps":
      return `${value} reps`;
  }
}
