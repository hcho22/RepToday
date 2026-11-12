/**
 * The Coach's server-side diet rail (M4, US-CA07, decision 29, FR-12).
 *
 * Diet guidance is general (protein, hydration, low carb, low sugar, vegetables), for adults only,
 * and never medical. The prompt says so, but the rail does not rest on the model obeying it:
 *
 * - The user's age is read from their own synced profile on the server (`ageGroup`), never from
 *   anything the app sends with the message. A profile with no readable age counts as under 18.
 * - For anyone not known to be 18 or over, a message about diet (`isDietTopic`) is answered with a
 *   fixed decline and never reaches the model.
 * - For the same users, a model reply that still talks about diet (`replyMentionsDiet`) is replaced
 *   by the same decline before it is stored or shown.
 *
 * The word lists are deliberately broad: a false positive only means a young user gets the decline
 * and a pointer back to training, which is the safe direction.
 */

export type AgeGroup = "adult" | "minor" | "unknown";

/** The age group the profile's onboarding age puts the user in. */
export function ageGroup(age: unknown): AgeGroup {
  if (typeof age !== "number" || !Number.isFinite(age) || age <= 0 || age > 120) {
    return "unknown";
  }
  return age >= 18 ? "adult" : "minor";
}

/** Whether diet guidance may be given to this age group. Only a known adult may receive it. */
export function mayDiscussDiet(group: AgeGroup): boolean {
  return group === "adult";
}

const DIET_TOPIC = new RegExp(
  "\\b(" +
    [
      "diet",
      "diets",
      "dieting",
      "nutrition",
      "nutritional",
      "nutrient",
      "nutrients",
      "protein",
      "proteins",
      "carb",
      "carbs",
      "carbohydrate",
      "carbohydrates",
      "sugar",
      "sugars",
      "sugary",
      "calorie",
      "calories",
      "macro",
      "macros",
      "meal",
      "meals",
      "eat",
      "eats",
      "eating",
      "ate",
      "food",
      "foods",
      "snack",
      "snacks",
      "breakfast",
      "lunch",
      "dinner",
      "hydration",
      "hydrate",
      "hydrated",
      "vegetable",
      "vegetables",
      "veggies",
      "fruit",
      "fruits",
      "fasting",
      "keto",
      "supplement",
      "supplements",
      "creatine",
      "whey",
      "vitamin",
      "vitamins",
      "lose weight",
      "losing weight",
      "weight loss",
      "fat loss",
      "bulk",
      "bulking",
      "drink",
      "drinking",
      "water intake",
    ].join("|") +
    ")\\b",
  "i",
);

/** Whether a user's message is about diet, eating, drinking or nutrition. */
export function isDietTopic(message: string): boolean {
  return DIET_TOPIC.test(message);
}

const DIET_REPLY = new RegExp(
  "\\b(" +
    [
      "diet",
      "dieting",
      "nutrition",
      "protein",
      "carb",
      "carbs",
      "carbohydrates?",
      "calories?",
      "macros?",
      "meal plan",
      "sugar",
      "vegetables",
      "veggies",
      "fasting",
      "keto",
      "supplements?",
      "creatine",
      "weight loss",
      "lose weight",
      "hydrat\\w*",
      "water intake",
    ].join("|") +
    ")\\b",
  "i",
);

/** Whether a model reply discusses diet. */
export function replyMentionsDiet(reply: string): boolean {
  return DIET_REPLY.test(reply);
}

/** The fixed reply a user under 18 (or of unknown age) gets for a diet question. */
export const DIET_DECLINE_REPLY =
  "Food and diet questions are outside what I can help with here. I can help with your training, though - " +
  "how to do a movement, what today's session is for, or a workout that fits the time you have.";
