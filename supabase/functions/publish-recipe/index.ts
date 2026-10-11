// publish-recipe: validates a recipe card and stores a read-only public copy in shared_recipes.
// Publishing requires a valid user access token. Reading remains public by slug.
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

const URL_ = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PUBLIC_KEYS = [Deno.env.get("SUPABASE_ANON_KEY"), ...(Deno.env.get("ATE_PUBLIC_KEYS") ?? "").split(",")]
  .map((k) => k?.trim()).filter(Boolean) as string[];
const admin = createClient(URL_, SERVICE, { auth: { persistSession: false } });

const str = (v: unknown, max: number, req = false) => {
  if (v == null || v === "") { if (req) throw "missing"; return null; }
  if (typeof v !== "string" || v.length > max) throw "bad string";
  return v.trim();
};
const num = (v: unknown, min: number, max: number, req = false) => {
  if (v == null) { if (req) throw "missing"; return null; }
  if (typeof v !== "number" || !isFinite(v) || v < min || v > max) throw "bad number";
  return v;
};
const httpsImage = (v: unknown) => { try { const s = str(v, 2000); return s && /^https:\/\//i.test(s) ? s : null; } catch { return null; } };
const httpURL = (v: unknown) => { const s = str(v, 2000); if (s && !/^https?:\/\//i.test(s)) throw "bad url"; return s; };

function validate(c: any) {
  if (!c || typeof c !== "object") throw "card";
  if (!Array.isArray(c.ingredients) || c.ingredients.length > 100) throw "ingredients";
  if (!Array.isArray(c.steps) || c.steps.length > 100) throw "steps";
  if (c.tags != null && (!Array.isArray(c.tags) || c.tags.length > 20)) throw "tags";
  const card = {
    title: str(c.title, 200, true)!,
    description: str(c.description, 1000),
    servings: Math.round(num(c.servings, 1, 200, true)!),
    timeMinutes: num(c.timeMinutes, 0, 10000),
    tags: (c.tags ?? []).map((t: unknown) => str(t, 60)).filter(Boolean),
    ingredients: c.ingredients.map((i: any) => ({
      name: str(i?.name, 200) ?? "", quantity: num(i?.quantity, 0, 1e6) ?? 0,
      unit: str(i?.unit, 30) ?? "", notes: str(i?.notes, 300) ?? "",
    })),
    steps: c.steps.map((s: any, n: number) => ({
      order: num(s?.order, 0, 1000) ?? n + 1, instruction: str(s?.instruction, 2000) ?? "",
      timeSeconds: num(s?.timeSeconds, 0, 86400),
    })),
    imageURL: httpsImage(c.imageURL ?? c.image_url),
    sourceURL: httpURL(c.sourceURL),
  };
  if (!card.ingredients.length && !card.steps.length) throw "empty";
  if (JSON.stringify(card).length > 100_000) throw "too large";
  return card;
}

const canon = (v: unknown): string =>
  Array.isArray(v) ? `[${v.map(canon).join(",")}]`
  : v && typeof v === "object" ? `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canon((v as any)[k])}`).join(",")}}`
  : JSON.stringify(v ?? null);
const slug = () => {
  const a = "0123456789abcdefghijklmnopqrstuvwxyz", b = crypto.getRandomValues(new Uint8Array(8));
  return Array.from(b, (x) => a[x % 36]).join("");
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return json(req, { error: "Method not allowed" }, 405);

  const bearer = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!bearer || PUBLIC_KEYS.includes(bearer)) {
    return json(req, { error: "Sign in to create a share link" }, 401);
  }
  const { data: authData, error: authError } = await admin.auth.getUser(bearer);
  if (authError || !authData.user) return json(req, { error: "Invalid session" }, 401);
  const userId = authData.user.id;

  const len = Number(req.headers.get("content-length") ?? 0);
  if (len > 200_000) return json(req, { error: "Recipe too large" }, 413);
  let card;
  try {
    const body = await req.json();
    card = validate(body?.card ?? body);
    if (!card.imageURL && body?.image_url) card.imageURL = httpsImage(body.image_url);
  } catch (e) {
    return json(req, { error: `Invalid recipe (${typeof e === "string" ? e : "json"})` }, 400);
  }

  const since = new Date(Date.now() - 10 * 60_000).toISOString();
  const { data: recent, count } = await admin.from("shared_recipes")
    .select("slug, card", { count: "exact" }).gte("created_at", since).eq("owner_id", userId).eq("title", card.title).limit(50);
  const same = recent?.find((r) => canon(r.card) === canon(card));
  if (same) return json(req, { slug: same.slug, reused: true });
  if ((count ?? 0) >= 20) return json(req, { error: "Too many shares, try again shortly" }, 429);
  const { count: burst } = await admin.from("shared_recipes").select("slug", { count: "exact", head: true })
    .eq("owner_id", userId).gte("created_at", new Date(Date.now() - 60_000).toISOString());
  if ((burst ?? 0) >= 20) return json(req, { error: "Too many shares, try again shortly" }, 429);

  for (let i = 0; i < 3; i++) {
    const s = slug();
    const { error } = await admin.from("shared_recipes").insert({
      slug: s, owner_id: userId, title: card.title, description: card.description, image_url: card.imageURL, card,
    });
    if (!error) {
      console.log(JSON.stringify({ published: s, user: userId }));
      return json(req, { slug: s });
    }
    if (error.code !== "23505") { console.error(error); break; }
  }
  return json(req, { error: "Could not publish this recipe right now." }, 500);
});
