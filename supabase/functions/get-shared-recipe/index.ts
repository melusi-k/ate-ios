// get-shared-recipe: public read of a shared recipe by slug. GET ?slug=abc12345 or POST { slug }.
// Mirrors Lovable's getSharedRecipe; the iOS app can also read shared_recipes via PostgREST (RLS: public SELECT).
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const json = (b: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json", ...extra } });

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { auth: { persistSession: false } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let slug = new URL(req.url).searchParams.get("slug");
  if (!slug && req.method === "POST") slug = (await req.json().catch(() => ({})))?.slug ?? null;
  if (!slug || !/^[a-z0-9]{4,40}$/i.test(slug)) return json({ error: "Invalid slug" }, 400);
  const { data, error } = await db.from("shared_recipes")
    .select("slug, title, description, image_url, card, created_at").eq("slug", slug).maybeSingle();
  if (error) return json({ error: "Lookup failed" }, 500);
  if (!data) return json({ error: "Not found" }, 404);
  return json(data, 200, { "Cache-Control": "public, max-age=300" });
});
