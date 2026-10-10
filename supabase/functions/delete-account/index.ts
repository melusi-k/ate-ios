// delete-account: permanently deletes the calling user (Apple guideline 5.1.1(v)).
// Requires the user's own access token (Authorization: Bearer <jwt>). Deletes their user_recipes rows,
// any shared_recipes they own (only if an owner column exists; today shares are anonymous and stay),
// then the auth user via the admin API.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token || token.startsWith("sb_")) return json({ error: "Sign in again to delete your account" }, 401);
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return json({ error: "Sign in again to delete your account" }, 401);
  const uid = data.user.id;

  const { error: e1, count } = await admin.from("user_recipes").delete({ count: "exact" }).eq("user_id", uid);
  if (e1) { console.error(e1); return json({ error: "Could not delete your data" }, 500); }

  let shared = 0;
  for (const col of ["user_id", "owner_id"]) {
    const { error: e2, count: c } = await admin.from("shared_recipes").delete({ count: "exact" }).eq(col, uid);
    if (!e2) { shared += c ?? 0; break; }
    if (e2.code !== "42703" && !/column/i.test(e2.message)) { console.error(e2); return json({ error: "Could not delete your shares" }, 500); }
  }

  const { error: e3 } = await admin.auth.admin.deleteUser(uid);
  if (e3) { console.error(e3); return json({ error: "Could not delete your account" }, 500); }
  console.log(JSON.stringify({ deleted: uid, user_recipes: count ?? 0, shared }));
  return json({ deleted: true, user_recipes: count ?? 0, shared_recipes: shared });
});
