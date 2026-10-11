// delete-account: permanently deletes the calling user (Apple guideline 5.1.1(v)).
// Requires the user's own access token and removes owned synced data and shares.
import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigin = Deno.env.get("ATE_WEB_ORIGIN") ?? "https://melusi-k.github.io";
const cors = (req: Request) => ({
  ...(req.headers.get("origin") === allowedOrigin ? { "Access-Control-Allow-Origin": allowedOrigin } : {}),
  "Vary": "Origin",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
});
const json = (req: Request, body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors(req), "Content-Type": "application/json" } });

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return json(req, { error: "Method not allowed" }, 405);
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token || token.startsWith("sb_")) return json(req, { error: "Sign in again to delete your account" }, 401);
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return json(req, { error: "Sign in again to delete your account" }, 401);
  const uid = data.user.id;

  const { error: e1, count } = await admin.from("user_recipes").delete({ count: "exact" }).eq("user_id", uid);
  if (e1) { console.error(e1); return json(req, { error: "Could not delete your data" }, 500); }

  const { error: e2, count: shared } = await admin.from("shared_recipes").delete({ count: "exact" }).eq("owner_id", uid);
  if (e2) { console.error(e2); return json(req, { error: "Could not delete your shared recipes" }, 500); }

  const { error: e3 } = await admin.auth.admin.deleteUser(uid);
  if (e3) { console.error(e3); return json(req, { error: "Could not delete your account" }, 500); }
  console.log(JSON.stringify({ deleted: uid, user_recipes: count ?? 0, shared: shared ?? 0 }));
  return json(req, { deleted: true, user_recipes: count ?? 0, shared_recipes: shared ?? 0 });
});
