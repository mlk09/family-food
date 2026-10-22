// CORS for the Flutter web/PWA build. Restrict ALLOWED_ORIGINS in production,
// e.g. "https://familyfood.example.com" (comma-separated). Native apps send no Origin.
const allowed = (Deno.env.get("ALLOWED_ORIGINS") ?? "*").split(",").map((s) => s.trim());

export function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  const allow = allowed.includes("*") ? "*" : (allowed.includes(origin) ? origin : allowed[0]);
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

export function json(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}
