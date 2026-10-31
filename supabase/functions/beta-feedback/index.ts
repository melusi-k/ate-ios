// Public-key-only beta feedback intake. Deploy with --no-verify-jwt.
// The function validates the public key, rate-limits by a one-way IP hash, and writes
// allowlisted fields using the service role. Never log submitted content or contact details.
import { createClient } from "npm:@supabase/supabase-js@2";

const projectURL = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const publicKeys = [Deno.env.get("SUPABASE_ANON_KEY"), ...(Deno.env.get("ATE_PUBLIC_KEYS") ?? "").split(",")]
  .map((key) => key?.trim()).filter(Boolean) as string[];
const admin = createClient(projectURL, serviceKey, { auth: { persistSession: false } });
const categories = new Set(["bug", "feature", "ux", "general"]);
const channels = new Set(["TierA", "TierB", "TierC", "Beta", "QA", "Internal", "Development"]);
const MAX_BODY_BYTES = 8_000;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

async function readBody(req: Request): Promise<string | null> {
  const declared = req.headers.get("content-length");
  if (declared !== null && (!Number.isFinite(Number(declared)) || Number(declared) > MAX_BODY_BYTES)) throw new RangeError();
  if (!req.body) return null;
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_BODY_BYTES) { await reader.cancel(); throw new RangeError(); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  try { return new TextDecoder("utf-8", { fatal: true }).decode(bytes); } catch { return null; }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!publicKeys.includes(req.headers.get("apikey") ?? "")) return json({ error: "Unauthorized" }, 401);

  const address = req.headers.get("cf-connecting-ip");
  if (!address || address.length > 128) return json({ error: "Rate limit identity unavailable" }, 503);
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(address));
  const keyHash = Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
  const { data: allowed, error: limitError } = await admin.rpc("consume_beta_feedback_rate_limit", { p_key_hash: keyHash });
  if (limitError) { console.error("feedback rate limiter unavailable"); return json({ error: "Feedback unavailable" }, 503); }
  if (allowed !== true) return json({ error: "Feedback limit reached. Please try again later." }, 429);

  let raw: string | null;
  try { raw = await readBody(req); } catch (error) {
    if (error instanceof RangeError) return json({ error: "Payload too large" }, 413);
    return json({ error: "Invalid request" }, 400);
  }
  if (raw === null) return json({ error: "Invalid request" }, 400);
  let body: any;
  try { body = JSON.parse(raw); } catch { return json({ error: "Invalid JSON" }, 400); }
  if (!body || typeof body !== "object" || Array.isArray(body) ||
      !categories.has(body.category) || typeof body.message !== "string" ||
      body.message.trim().length < 10 || body.message.length > 5000 ||
      body.message !== body.message.trim() || !channels.has(body.channel) ||
      typeof body.appVersion !== "string" || !body.appVersion.trim() || body.appVersion.length > 32 ||
      typeof body.buildNumber !== "string" || !body.buildNumber.trim() || body.buildNumber.length > 32 ||
      typeof body.gitSHA !== "string" || !body.gitSHA.trim() || body.gitSHA.length > 16 ||
      (body.contactEmail != null && (typeof body.contactEmail !== "string" ||
        body.contactEmail.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.contactEmail)))) {
    return json({ error: "Please check your feedback details." }, 400);
  }
  const { error } = await admin.from("beta_feedback").insert({
    category: body.category,
    message: body.message,
    contact_email: body.contactEmail || null,
    app_version: body.appVersion,
    build_number: body.buildNumber,
    channel: body.channel,
    git_sha: body.gitSHA,
    platform: "iOS",
  });
  if (error) { console.error("feedback insert failed"); return json({ error: "Feedback could not be saved." }, 503); }
  return json({ accepted: true }, 202);
});
