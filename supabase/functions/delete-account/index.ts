// Permanently deletes the calling user's account. Uses the service-role key,
// which exists only here on the server. All app rows cascade-delete via FKs.

import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "method_not_allowed" }, 405);

  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const userClient = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { data, error } = await userClient.auth.getUser(token);
  if (error || !data.user) return json(req, { error: "unauthorized" }, 401);
  const uid = data.user.id;

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  // Leave the family first so admin rights pass to another member.
  await admin.rpc("leave_family_for", { p_user: uid }).then(() => {}, () => {});

  // Remove avatar files.
  const { data: files } = await admin.storage.from("avatars").list(uid);
  if (files?.length) await admin.storage.from("avatars").remove(files.map((f) => `${uid}/${f.name}`));

  const { error: delErr } = await admin.auth.admin.deleteUser(uid);
  if (delErr) {
    console.error("delete user failed", delErr.message);
    return json(req, { error: "delete_failed" }, 500);
  }
  return json(req, { ok: true });
});
