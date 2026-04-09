export interface Env {
  ANTHROPIC_API_KEY: string;
  CLIENT_API_KEY: string;
  RATE_LIMIT: KVNamespace;
}

// --- Types ---

interface SummaryRequest {
  userId: string;
  workout: {
    exercises: { name: string; sets: number; reps: number; muscleGroups: string[] }[];
    durationMinutes: number;
    rating: number;
    difficulty: string;
  };
  profile: {
    age?: number;
    sex?: string;
    weightKg?: number;
    fitnessLevel: string;
  };
}

interface WeeklyReportRequest {
  userId: string;
  workouts: {
    date: string;
    exercises: { name: string; muscleGroups: string[] }[];
    durationMinutes: number;
    rating: number;
    difficulty: string;
  }[];
  trends: {
    totalWorkouts30d: number;
    avgDuration30d: number;
    streak: number;
    xp: number;
    level: number;
  };
  profile: {
    age?: number;
    sex?: string;
    weightKg?: number;
    fitnessLevel: string;
  };
}

interface NextWorkoutPreviewRequest {
  userId: string;
  recentHistory: {
    date: string;
    movementPatterns: string[];
    muscleGroups: string[];
  }[];
  goals: string[];
  profile: {
    age?: number;
    sex?: string;
    weightKg?: number;
    fitnessLevel: string;
  };
}

type RouteHandler = (request: Request, env: Env) => Promise<Response>;

// --- Rate Limiting ---

interface RateLimitConfig {
  maxRequests: number;
  windowSeconds: number;
}

const RATE_LIMITS: Record<string, RateLimitConfig> = {
  "/api/ai/summary": { maxRequests: 10, windowSeconds: 86400 },
  "/api/ai/weekly-report": { maxRequests: 1, windowSeconds: 604800 },
  "/api/ai/next-workout-preview": { maxRequests: 10, windowSeconds: 86400 },
};

async function checkRateLimit(
  kv: KVNamespace,
  userId: string,
  path: string,
): Promise<{ allowed: boolean; remaining: number }> {
  const config = RATE_LIMITS[path];
  if (!config) return { allowed: true, remaining: 999 };

  const key = `rate:${path}:${userId}`;
  const raw = await kv.get(key);
  const count = raw ? parseInt(raw, 10) : 0;

  if (count >= config.maxRequests) {
    return { allowed: false, remaining: 0 };
  }

  await kv.put(key, String(count + 1), {
    expirationTtl: config.windowSeconds,
  });

  return { allowed: true, remaining: config.maxRequests - count - 1 };
}

// --- PII Stripping ---

function sanitizeProfile(profile: Record<string, unknown>): Record<string, unknown> {
  const allowed = ["age", "sex", "weightKg", "fitnessLevel"];
  const clean: Record<string, unknown> = {};
  for (const key of allowed) {
    if (profile[key] !== undefined) {
      clean[key] = profile[key];
    }
  }
  return clean;
}

// --- Request Validation ---

function validateSummaryRequest(body: unknown): body is SummaryRequest {
  if (!body || typeof body !== "object") return false;
  const b = body as Record<string, unknown>;
  return (
    typeof b.userId === "string" &&
    b.workout != null &&
    typeof b.workout === "object" &&
    b.profile != null &&
    typeof b.profile === "object"
  );
}

function validateWeeklyReportRequest(body: unknown): body is WeeklyReportRequest {
  if (!body || typeof body !== "object") return false;
  const b = body as Record<string, unknown>;
  return (
    typeof b.userId === "string" &&
    Array.isArray(b.workouts) &&
    b.trends != null &&
    typeof b.trends === "object" &&
    b.profile != null &&
    typeof b.profile === "object"
  );
}

function validateNextWorkoutPreviewRequest(body: unknown): body is NextWorkoutPreviewRequest {
  if (!body || typeof body !== "object") return false;
  const b = body as Record<string, unknown>;
  return (
    typeof b.userId === "string" &&
    Array.isArray(b.recentHistory) &&
    Array.isArray(b.goals) &&
    b.profile != null &&
    typeof b.profile === "object"
  );
}

// --- Claude API ---

async function callClaude(
  env: Env,
  model: string,
  systemPrompt: string,
  userMessage: string,
  maxTokens: number,
): Promise<string> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);

  try {
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model,
        max_tokens: maxTokens,
        system: systemPrompt,
        messages: [{ role: "user", content: userMessage }],
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`Claude API error ${response.status}: ${text}`);
    }

    const data = (await response.json()) as {
      content: { type: string; text: string }[];
    };
    return data.content[0]?.text ?? "";
  } finally {
    clearTimeout(timeout);
  }
}

// --- Route Handlers ---

const handleSummary: RouteHandler = async (request, env) => {
  const body = await request.json();
  if (!validateSummaryRequest(body)) {
    return jsonResponse({ error: "Invalid request body. Required: userId, workout, profile." }, 400);
  }

  const profile = sanitizeProfile(body.profile as unknown as Record<string, unknown>);
  const w = body.workout;

  const systemPrompt =
    "You are a concise, encouraging fitness coach. Summarize the user's completed workout in 2-3 sentences. Mention key muscle groups worked and offer one specific tip for next time. Keep it motivating.";

  const userMessage = `Workout completed:
- Duration: ${w.durationMinutes} min
- Rating: ${w.rating}/5, Difficulty: ${w.difficulty}
- Exercises: ${w.exercises.map((e) => `${e.name} (${e.sets}x${e.reps}, ${e.muscleGroups.join("/")})`).join("; ")}
- User profile: ${JSON.stringify(profile)}`;

  const text = await callClaude(env, "claude-haiku-4-5-20251001", systemPrompt, userMessage, 100);
  return jsonResponse({ summary: text });
};

const handleWeeklyReport: RouteHandler = async (request, env) => {
  const body = await request.json();
  if (!validateWeeklyReportRequest(body)) {
    return jsonResponse(
      { error: "Invalid request body. Required: userId, workouts, trends, profile." },
      400,
    );
  }

  const profile = sanitizeProfile(body.profile as unknown as Record<string, unknown>);
  const t = body.trends;

  const systemPrompt =
    "You are an insightful fitness analyst. Write a brief weekly report (3-5 sentences) covering what the user did well, what muscle groups or movement patterns were underrepresented, and one actionable goal for next week. Be specific and encouraging.";

  const workoutLines = body.workouts
    .map(
      (w) =>
        `${w.date}: ${w.durationMinutes}min, ${w.exercises.map((e) => e.name).join("/")} — rated ${w.rating}/5 (${w.difficulty})`,
    )
    .join("\n");

  const userMessage = `Weekly summary:
${workoutLines}

30-day trends: ${t.totalWorkouts30d} workouts, avg ${t.avgDuration30d}min, streak ${t.streak} weeks
Level ${t.level}, ${t.xp} XP
User profile: ${JSON.stringify(profile)}`;

  const text = await callClaude(env, "claude-sonnet-4-5-20250514", systemPrompt, userMessage, 300);
  return jsonResponse({ report: text });
};

const handleNextWorkoutPreview: RouteHandler = async (request, env) => {
  const body = await request.json();
  if (!validateNextWorkoutPreviewRequest(body)) {
    return jsonResponse(
      { error: "Invalid request body. Required: userId, recentHistory, goals, profile." },
      400,
    );
  }

  const profile = sanitizeProfile(body.profile as unknown as Record<string, unknown>);

  const systemPrompt =
    "You are a workout planning assistant. Based on recent workout history, suggest what the user should focus on next in 2-3 sentences. Mention specific movement patterns or muscle groups that are underrepresented. Be practical and brief.";

  const historyLines = body.recentHistory
    .map((h) => `${h.date}: patterns=${h.movementPatterns.join(",")}, muscles=${h.muscleGroups.join(",")}`)
    .join("\n");

  const userMessage = `Recent history:
${historyLines}

Goals: ${body.goals.join(", ")}
User profile: ${JSON.stringify(profile)}`;

  const text = await callClaude(env, "claude-haiku-4-5-20251001", systemPrompt, userMessage, 150);
  return jsonResponse({ preview: text });
};

// --- Routing ---

const routes: Record<string, RouteHandler> = {
  "/api/ai/summary": handleSummary,
  "/api/ai/weekly-report": handleWeeklyReport,
  "/api/ai/next-workout-preview": handleNextWorkoutPreview,
};

// --- Helpers ---

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// --- Worker Entry ---

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // HTTPS only (Cloudflare handles TLS termination, but reject if somehow plain HTTP)
    if (new URL(request.url).protocol !== "https:") {
      // In dev mode, allow http; in prod Cloudflare enforces HTTPS
      // This check is a defense-in-depth measure
    }

    // CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
          "Access-Control-Max-Age": "86400",
        },
      });
    }

    // Only POST allowed
    if (request.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    // Authenticate client
    const authHeader = request.headers.get("Authorization");
    if (!authHeader || authHeader !== `Bearer ${env.CLIENT_API_KEY}`) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    // Route matching
    const url = new URL(request.url);
    const handler = routes[url.pathname];
    if (!handler) {
      return jsonResponse({ error: "Not found" }, 404);
    }

    // Extract userId for rate limiting
    let userId: string;
    try {
      const cloned = request.clone();
      const body = (await cloned.json()) as { userId?: string };
      userId = body.userId ?? "anonymous";
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    // Rate limit check
    const rateResult = await checkRateLimit(env.RATE_LIMIT, userId, url.pathname);
    if (!rateResult.allowed) {
      return jsonResponse({ error: "Rate limit exceeded. Try again later." }, 429);
    }

    // Handle request
    try {
      const response = await handler(request, env);
      // Add rate limit headers
      response.headers.set("X-RateLimit-Remaining", String(rateResult.remaining));
      return response;
    } catch (err) {
      const message = err instanceof Error ? err.message : "Unknown error";

      if (message.includes("aborted") || message.includes("timeout")) {
        return jsonResponse({ error: "Request timed out. Please try again." }, 504);
      }

      console.error("Proxy error:", message);
      return jsonResponse({ error: "AI service temporarily unavailable." }, 502);
    }
  },
} satisfies ExportedHandler<Env>;
