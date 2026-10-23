// Public, category-only telemetry ingestion for non-production Ate builds.
// Deploy with --no-verify-jwt: this endpoint intentionally accepts the app's public publishable key,
// validates it below, and never accepts a user session or service-role key from the client.
import { createClient } from "npm:@supabase/supabase-js@2";

const projectURL = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const publicKeys = [Deno.env.get("SUPABASE_ANON_KEY"), ...(Deno.env.get("ATE_PUBLIC_KEYS") ?? "").split(",")]
  .map((key) => key?.trim()).filter(Boolean) as string[];
const admin = createClient(projectURL, serviceKey, { auth: { persistSession: false } });
const kinds = new Set([
  "appLaunched", "appForegrounded", "appBackgrounded",
  "storeOpenFailed", "storeRecovered", "storeInMemoryFallback", "saveFailed",
  "recipeImportSucceeded", "recipeImportFailed", "recipeSaved",
  "cookingSessionCompleted", "insightViewed", "insightActionSelected",
  "syncSucceeded", "syncFailed",
]);
const channels = new Set(["TierA", "TierB", "TierC", "Beta", "QA", "Internal", "Development"]);
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

function boundedString(value: unknown, max: number): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= max && value.trim() === value;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const key = req.headers.get("apikey") ?? "";
  if (!key || !publicKeys.includes(key)) return json({ error: "Unauthorized" }, 401);

  const declaredLength = Number(req.headers.get("content-length") ?? 0);
  if (declaredLength > 12_000) return json({ error: "Payload too large" }, 413);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  if (!body || typeof body !== "object" || !channels.has(body.channel) ||
      !boundedString(body.appVersion, 32) || !boundedString(body.buildNumber, 32) ||
      !boundedString(body.gitSHA, 16) || !Array.isArray(body.events) ||
      body.events.length < 1 || body.events.length > 20) {
    return json({ error: "Invalid telemetry envelope" }, 400);
  }

  const now = Date.now();
  const rows = [];
  for (const event of body.events) {
    if (!event || typeof event !== "object" || !kinds.has(event.kind) ||
        typeof event.timestamp !== "number" || !Number.isFinite(event.timestamp) ||
        event.timestamp < now - 7 * 24 * 60 * 60 * 1000 || event.timestamp > now + 5 * 60 * 1000) {
      return json({ error: "Invalid telemetry event" }, 400);
    }
    // Deliberately construct a fresh allowlisted object; unknown client fields are never persisted.
    rows.push({
      event_kind: event.kind,
      channel: body.channel,
      app_version: body.appVersion,
      build_number: body.buildNumber,
      git_sha: body.gitSHA,
      platform: "iOS",
      occurred_at: new Date(event.timestamp).toISOString(),
    });
  }

  // Best-effort retention cleanup. Ingestion is not blocked if cleanup cannot run.
  await admin.from("app_telemetry_events").delete()
    .lt("received_at", new Date(now - 30 * 24 * 60 * 60 * 1000).toISOString());

  const { error } = await admin.from("app_telemetry_events").insert(rows);
  if (error) {
    // Do not log payloads, event names, keys, or request headers.
    console.error("telemetry insert failed");
    return json({ error: "Telemetry unavailable" }, 503);
  }
  return json({ accepted: rows.length }, 202);
});
