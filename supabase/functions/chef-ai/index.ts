// Chef AI — secure server-side proxy between the Flutter app and OpenAI.
//
// Flutter ─▶ this Edge Function (verifies the user, rate-limits, builds prompts,
//            enforces JSON schemas) ─▶ OpenAI ─▶ validated JSON / streamed text ─▶ Flutter
//
// Secrets (set with `supabase secrets set ...`, never in the app):
//   OPENAI_API_KEY        required
//   OPENAI_MODEL          optional, default "gpt-4o-mini"
//   OPENAI_VISION_MODEL   optional, defaults to OPENAI_MODEL
//   DAILY_AI_LIMIT        optional, requests per user per day (default 80)
//   ALLOW_DEMO_AI         optional, "true" lets Demo Mode (anon key) use AI
//   ALLOWED_ORIGINS       optional, CORS allow-list for the web app
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected by Supabase.

import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import { schemas, systemPrompt, userPrompt, type Ctx } from "./prompts.ts";

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const MODEL = Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini";
const VISION_MODEL = Deno.env.get("OPENAI_VISION_MODEL") ?? MODEL;
const DAILY_LIMIT = Number(Deno.env.get("DAILY_AI_LIMIT") ?? "80");
const ALLOW_DEMO_AI = Deno.env.get("ALLOW_DEMO_AI") === "true";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const ACTIONS = new Set(["generate_recipes", "recipe_detail", "meal_plan", "substitutions", "shopping_list", "scan_ingredients", "chat"]);
const MAX_BODY_BYTES = 2_000_000; // ~1.4 MB image after base64
const TIMEOUT_MS = 40_000;

const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

async function identify(req: Request): Promise<{ userId: string | null; demo: boolean }> {
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return { userId: null, demo: false };
  // Public client keys (legacy anon JWT or new sb_publishable_ key) = Demo Mode.
  if (token === ANON_KEY || token.startsWith("sb_publishable_")) return { userId: null, demo: true };
  const client = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) return { userId: null, demo: false };
  return { userId: data.user.id, demo: false };
}

// Reasoning models (o-series, gpt-5 family) reject custom temperature.
const supportsTemperature = (model: string) => !/^(o\d|gpt-5)/i.test(model);

async function openai(body: Record<string, unknown>, signal: AbortSignal): Promise<Response> {
  const model = String(body.model);
  if (!supportsTemperature(model)) delete body.temperature;
  return await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "Authorization": `Bearer ${OPENAI_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal,
  });
}

/** Logs an OpenAI failure and returns a safe error with OpenAI's error code (no secrets). */
async function upstreamError(req: Request, label: string, res: Response): Promise<Response> {
  const text = await res.text();
  console.error("openai", label, res.status, text);
  let detail = `http_${res.status}`;
  try {
    const e = JSON.parse(text)?.error;
    detail = String(e?.code || e?.type || detail);
  } catch { /* not JSON */ }
  return json(req, { error: "ai_unavailable", detail }, 502);
}

/** Re-checks structured output server-side; the app validates again. */
// deno-lint-ignore no-explicit-any
function sanitize(action: string, data: any): any {
  const clean = (s: unknown, n = 300) => String(s ?? "").slice(0, n);
  // deno-lint-ignore no-explicit-any
  const recipe = (r: any) =>
    r && typeof r.name === "string" && Array.isArray(r.ingredients) && r.ingredients.length && Array.isArray(r.instructions) && r.instructions.length
      ? {
        ...r,
        name: clean(r.name, 80),
        description: clean(r.description, 300),
        emoji: clean(r.emoji, 8) || "🍽️",
        prep_time: Math.max(0, Math.min(600, Number(r.prep_time) || 10)),
        cook_time: Math.max(0, Math.min(1440, Number(r.cook_time) || 15)),
        servings: Math.max(1, Math.min(50, Number(r.servings) || 2)),
        instructions: r.instructions.slice(0, 20).map((s: unknown) => clean(s, 400)),
      }
      : null;
  switch (action) {
    case "generate_recipes":
      return { recipes: (Array.isArray(data?.recipes) ? data.recipes : []).map(recipe).filter(Boolean).slice(0, 6) };
    case "recipe_detail":
      return { recipe: recipe(data?.recipe) };
    default:
      return data;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "method_not_allowed" }, 405);
  if (!OPENAI_API_KEY) return json(req, { error: "ai_not_configured" }, 503);

  const len = Number(req.headers.get("content-length") ?? "0");
  if (len > MAX_BODY_BYTES) return json(req, { error: "too_large" }, 413);

  const { userId, demo } = await identify(req);
  if (!userId && !(demo && ALLOW_DEMO_AI)) return json(req, { error: "unauthorized" }, 401);

  // deno-lint-ignore no-explicit-any
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json(req, { error: "bad_json" }, 400);
  }
  const action = String(body?.action ?? "");
  if (!ACTIONS.has(action)) return json(req, { error: "unknown_action" }, 400);

  if (userId) {
    const { data: ok, error } = await admin.rpc("increment_ai_usage", { p_user: userId, p_limit: DAILY_LIMIT });
    if (error) console.error("usage error", error.message);
    if (ok === false) return json(req, { error: "rate_limited" }, 429);
  }

  const ctx: Ctx = typeof body.context === "object" && body.context ? body.context : {};
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    // ── Streaming chat ──
    if (action === "chat") {
      const history = (Array.isArray(body.messages) ? body.messages : [])
        .filter((m: { role?: string }) => m && (m.role === "user" || m.role === "assistant"))
        .slice(-16)
        .map((m: { role: string; content?: string }) => ({ role: m.role, content: String(m.content ?? "").slice(0, 2000) }));
      if (!history.length) return json(req, { error: "empty" }, 400);
      const recipe = body.recipe ? `\nThe user is looking at this recipe: ${String(body.recipe).slice(0, 4000)}` : "";
      const upstream = await openai({
        model: MODEL,
        stream: true,
        temperature: 0.6,
        max_completion_tokens: 1200,
        messages: [
          { role: "system", content: systemPrompt(ctx) + recipe + "\nAnswer concisely (under 180 words) with short bullet points where helpful." },
          ...history,
        ],
      }, controller.signal);
      if (!upstream.ok || !upstream.body) {
        return await upstreamError(req, "chat", upstream);
      }
      // Convert OpenAI SSE into a plain text stream of content deltas.
      const decoder = new TextDecoder();
      const encoder = new TextEncoder();
      let buffer = "";
      const stream = new ReadableStream({
        async start(out) {
          const reader = upstream.body!.getReader();
          try {
            while (true) {
              const { value, done } = await reader.read();
              if (done) break;
              buffer += decoder.decode(value, { stream: true });
              const lines = buffer.split("\n");
              buffer = lines.pop() ?? "";
              for (const line of lines) {
                const t = line.trim();
                if (!t.startsWith("data:")) continue;
                const payload = t.slice(5).trim();
                if (payload === "[DONE]") continue;
                try {
                  const delta = JSON.parse(payload).choices?.[0]?.delta?.content;
                  if (delta) out.enqueue(encoder.encode(delta));
                } catch { /* partial line */ }
              }
            }
          } catch (e) {
            console.error("stream error", e);
          } finally {
            clearTimeout(timer);
            out.close();
          }
        },
      });
      return new Response(stream, {
        headers: { ...corsHeaders(req), "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-cache" },
      });
    }

    // ── Vision: scan ingredients ──
    if (action === "scan_ingredients") {
      const b64 = String(body.image_base64 ?? "");
      if (!b64 || b64.length > MAX_BODY_BYTES) return json(req, { error: "bad_image" }, 400);
      const res = await openai({
        model: VISION_MODEL,
        temperature: 0.2,
        response_format: { type: "json_schema", json_schema: schemas.scan_ingredients },
        messages: [
          { role: "system", content: "You identify food ingredients in photos of kitchens, fridges and groceries. Return only clearly visible edible items with simple common names (e.g. \"tomato\", \"milk\"). Ignore people, brands and non-food items." },
          { role: "user", content: [
            { type: "text", text: "List the food ingredients you can see." },
            { type: "image_url", image_url: { url: `data:image/jpeg;base64,${b64}`, detail: "low" } },
          ] },
        ],
      }, controller.signal);
      if (!res.ok) {
        return await upstreamError(req, "vision", res);
      }
      const out = await res.json();
      return json(req, JSON.parse(out.choices?.[0]?.message?.content ?? "{\"ingredients\":[]}"));
    }

    // ── Structured JSON actions ──
    const schema = schemas[action as keyof typeof schemas];
    const res = await openai({
      model: MODEL,
      temperature: action === "meal_plan" || action === "generate_recipes" ? 0.8 : 0.5,
      response_format: { type: "json_schema", json_schema: schema },
      messages: [
        { role: "system", content: systemPrompt(ctx) },
        { role: "user", content: userPrompt(action, body) },
      ],
    }, controller.signal);
    if (!res.ok) {
      return await upstreamError(req, action, res);
    }
    const out = await res.json();
    const content = out.choices?.[0]?.message?.content;
    if (!content) return json(req, { error: "empty_response" }, 502);
    let parsed: unknown;
    try {
      parsed = JSON.parse(content);
    } catch {
      return json(req, { error: "malformed_response" }, 502);
    }
    return json(req, sanitize(action, parsed));
  } catch (e) {
    const aborted = e instanceof DOMException && e.name === "AbortError";
    console.error("chef-ai error", e);
    return json(req, { error: aborted ? "timeout" : "server_error" }, aborted ? 504 : 500);
  } finally {
    if (action !== "chat") clearTimeout(timer);
  }
});
