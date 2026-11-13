/**
 * The Coach's server-side rails (M4, US-CA07, ADR-0017; widened by ADR-0019, US-HC01/US-HC03).
 *
 * Two deterministic rails run on the server around the one model call; neither rests on the model
 * obeying its instructions.
 *
 * The crisis rail, at every age (`supportTopic`): a message that plainly speaks of suicide, self-harm
 * or disordered eating gets a short, caring redirect to professional help and never reaches the model.
 * It runs before the diet rail, so a young user's message about starving themselves gets the redirect
 * rather than the diet decline. It matches only unambiguous phrases ("this workout is killing me" is
 * not one); everything subtler is left to the instructions, which carry the same redirect.
 *
 * The diet rail, for anyone not known to be 18 or over:
 *
 * - The user's age is read from their own synced profile on the server (`ageGroup`), never from
 *   anything the app sends with the message. A profile with no readable age counts as under 18.
 * - A message about food, diet, supplements or weight (`isDietTopic`) is answered with a fixed decline
 *   and never reaches the model.
 * - A model reply that still talks about them (`replyMentionsDiet`) is replaced by the same decline
 *   before it is stored or shown.
 *
 * Plain hydration - how much water to drink around training - is open to every age (decision 12), so
 * water, drinking and hydration are on neither word list; food and meals, drinks other than water,
 * protein shakes, supplements, caffeine, weight loss and weight management are on both. Sleep, stress, recovery, cardio and other training
 * are open to every age and must never trip the rail. Otherwise the lists are deliberately broad: a
 * false positive only means a young user gets the decline and a pointer back to training, sleep and
 * recovery, which is the safe direction.
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

/** Regex alternatives matched as whole words, case-insensitively. */
function wholeWords(alternatives: string[]): RegExp {
  return new RegExp(`\\b(${alternatives.join("|")})\\b`, "i");
}

// MARK: - The crisis rail (every age)

const CRISIS_TOPIC = wholeWords([
  "suicide(?!\\s+(sprints?|runs?|drills?|squeeze))",
  "suicidal",
  "kill myself",
  "killing myself",
  "end my life",
  "ending my life",
  "take my (own )?life",
  "i (just |really |honestly |kind of |sometimes )?(want|wanna) to die",
  "i (just |really |honestly |kind of |sometimes )?wanna die",
  "wish i (was|were) dead",
  "better off dead",
  "don'?t want to (live|be alive|be here anymore)",
  "no reason to live",
  "self[- ]?harm(ing)?",
  "cutting myself",
  "(?<!(can|could) (you|i|someone|people|a person) |possible to )overdos(e|ed|ing)",
]);

const DISORDERED_EATING_TOPIC = wholeWords([
  "eating disorders?",
  "anorexi[ac]",
  "bulimi[ac]",
  "binge[- ]?(eat|eating|ate|and purge)",
  "binging and purging",
  "(purg(e|es|ed|ing)|(make|made|making) myself sick) after (i eat|i ate|i've eaten|eating|every meal|meals?|breakfast|lunch|dinner|food)",
  "(make|made|making) myself (throw up|throw (it|it all|everything|food) up|vomit|puke)",
  "starv(e|ed|ing) myself",
  "stop(ped)? eating (completely|entirely|altogether)",
  "(haven'?t|have not|hardly|barely) eaten in (days|a week|\\w+ days)",
  "scared to eat",
  "afraid to eat",
  "hate myself (after|for) eating",
]);

const MEAL = "(meals?|breakfast|lunch|dinner|food|eating)";
const TO_LOSE_OR_MAKE_UP = "(to|so i can|so i) (lose weight|make up|burn|get thin|be thin|stay thin|lose fat)";

/** Wider signals for anyone not known to be an adult, whose food question would otherwise meet the diet decline. */
const YOUNG_EATING_SIGNAL = wholeWords([
  `(vomit(s|ed|ing)?|throw(s|ing)? up|threw up) after (i eat|i ate|i've eaten|eating|every meal|${MEAL})`,
  `skip(s|ped|ping)? (most |all |my |some |a lot of )?${MEAL} ${TO_LOSE_OR_MAKE_UP}`,
  "(guilty|ashamed|disgusted with myself) (whenever|when|after|every time|about|for) (i eat|i've eaten|i ate|eating|food)",
  "hate my body\\b[\\s\\S]*\\b(eat|eating|ate|food|meals?|vomit|purg(e|ing))",
  `(eat|eating|ate|food|meals?)\\b[\\s\\S]*\\bhate my body`,
]);

/** For an adult, only first-person disclosures: a question about skipping a meal or feeling guilty reaches the model. */
const ADULT_EATING_DISCLOSURE = wholeWords([
  `i('ve| have|'m| am)? (been |keep |kept |always |often )?skip(s|ped|ping)? (most |all |my |some |a lot of )?${MEAL} ${TO_LOSE_OR_MAKE_UP}`,
  "i (feel|felt|get) (so |really |very )?(guilty|ashamed|disgusted with myself) (whenever|every time|each time) (i eat|i've eaten|i ate)",
]);

/** Which professional-help redirect a message calls for, if any. */
export type SupportTopic = "crisis" | "disorderedEating";

/**
 * Whether a user's message plainly speaks of a crisis or disordered eating. For anyone not known to be an
 * adult the eating signals are wider, so a disclosure never meets the diet decline; an adult's question
 * about skipping meals or eating guilt reaches the model, whose instructions carry the same redirect.
 */
export function supportTopic(message: string, group: AgeGroup): SupportTopic | null {
  if (CRISIS_TOPIC.test(message)) return "crisis";
  if (DISORDERED_EATING_TOPIC.test(message)) return "disorderedEating";
  if ((mayDiscussDiet(group) ? ADULT_EATING_DISCLOSURE : YOUNG_EATING_SIGNAL).test(message)) return "disorderedEating";
  return null;
}

/** The fixed, caring redirect for a message about suicide or self-harm, at every age. */
export const CRISIS_SUPPORT_REPLY =
  "I'm really glad you told me, and I'm sorry you're carrying this. It's bigger than what I can help with here, " +
  "and you deserve real support. Please reach out to a doctor, a mental health professional, or someone you trust today. " +
  "If you might act on these thoughts or you're in danger, contact your local emergency services now.";

/** The fixed, caring redirect for a message about disordered eating, at every age. */
export const EATING_SUPPORT_REPLY =
  "Thank you for telling me. What you're going through with food deserves care from someone who can really help, " +
  "and that's not something I can do here. Please reach out to a doctor or a mental health professional, or talk to someone you trust. " +
  "If you ever feel unsafe, contact your local emergency services.";

/** The fixed reply for a support topic. */
export function supportReply(topic: SupportTopic): string {
  return topic === "crisis" ? CRISIS_SUPPORT_REPLY : EATING_SUPPORT_REPLY;
}

// MARK: - The diet rail (under 18 or unknown age)

const DIET_TOPIC = wholeWords([
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
  "caffeine",
  "coffee",
  "energy drinks?",
  "protein shakes?",
  "milkshakes?",
  "smoothies?",
  "soda",
  "sports drinks?",
  "juices?",
  "milk",
  "beers?",
  "wine",
  "alcohol",
  "lose weight",
  "losing weight",
  "weight loss",
  "gain weight",
  "gaining weight",
  "weight gain",
  "put on weight",
  "weight management",
  "manag(e|ing) my weight",
  "fat loss",
  "lose fat",
  "losing fat",
  "burn fat",
  "burning fat",
  "body fat",
  "bmi",
  "(lose|drop|shed) \\d+ ?(pounds|lbs?|kg|kilos?)",
  "bulk",
  "bulking",
]);

/** Whether a user's message is about food, diet, supplements or weight. Plain water and hydration are not. */
export function isDietTopic(message: string): boolean {
  return DIET_TOPIC.test(message);
}

const DIET_REPLY = wholeWords([
  "diet",
  "dieting",
  "nutrition",
  "protein",
  "carb",
  "carbs",
  "carbohydrates?",
  "calories?",
  "macros?",
  "meals?",
  "meal plan",
  "eat",
  "eats",
  "eating",
  "ate",
  "foods?",
  "snacks?",
  "breakfast",
  "lunch",
  "dinner",
  "fruits?",
  "smoothies?",
  "sugar",
  "vegetables",
  "veggies",
  "fasting",
  "keto",
  "supplements?",
  "creatine",
  "whey",
  "caffeine",
  "coffee",
  "energy drinks?",
  "sports drinks?",
  "juices?",
  "milk",
  "beers?",
  "wine",
  "alcohol",
  "weight loss",
  "lose weight",
  "losing weight",
  "gain weight",
  "gaining weight",
  "weight gain",
  "weight management",
  "fat loss",
  "body fat",
  "bulk",
  "bulking",
]);

/** Whether a model reply discusses diet, supplements or weight. Plain water and hydration do not count. */
export function replyMentionsDiet(reply: string): boolean {
  return DIET_REPLY.test(reply);
}

/**
 * The fixed reply a user under 18 (or of unknown age) gets for a diet question. Its first sentence is
 * what `CoachEndToEndUITests` recognises it by.
 */
export const DIET_DECLINE_REPLY =
  "Food and diet questions are outside what I can help with here. I can help with your training, sleep and recovery, though - " +
  "how to do a movement, what today's session is for, or a workout that fits the time you have.";

// MARK: - The rails around one turn

/**
 * The fixed reply the server gives a message before any model call, or null when the message may reach
 * the model: the crisis rail first, at every age, then the diet rail for anyone not known to be an adult.
 */
export function replyBeforeModel(message: string, group: AgeGroup): string | null {
  const support = supportTopic(message, group);
  if (support !== null) return supportReply(support);
  if (!mayDiscussDiet(group) && isDietTopic(message)) return DIET_DECLINE_REPLY;
  return null;
}

/** A model reply as the diet rail lets it through: replaced by the decline if it drifted into diet for a user not known to be an adult. */
export function replyAfterModel(reply: string, group: AgeGroup): string {
  return !mayDiscussDiet(group) && replyMentionsDiet(reply) ? DIET_DECLINE_REPLY : reply;
}
