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
const MAX_BODY_BYTES = 12_000;
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

async function readBoundedBody(req: Request): Promise<string | null> {
  // Reject declared oversize bodies early, but enforce the same limit while streaming because
  // Content-Length may be absent or untrustworthy.
  const declaredLength = req.headers.get("content-length");
  if (declaredLength !== null) {
    const parsedLength = Number(declaredLength);
    if (!Number.isFinite(parsedLength) || parsedLength < 0) return null;
    if (parsedLength > MAX_BODY_BYTES) throw new RangeError("payload too large");
  }
  if (!req.body) return null;
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_BODY_BYTES) {
        await reader.cancel();
        throw new RangeError("payload too large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return null;
  }
}

async function rateLimitKey(req: Request): Promise<string | null> {
  // Only hash the trusted platform-provided client address; never persist the raw address.
  // If the platform address is unavailable, fail closed rather than expose an unlimited endpoint.
  const address = req.headers.get("cf-connecting-ip");
  if (!address || address.length > 128) return null;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(address));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const key = req.headers.get("apikey") ?? "";
  if (!key || !publicKeys.includes(key)) return json({ error: "Unauthorized" }, 401);

  const hashedAddress = await rateLimitKey(req);
  if (!hashedAddress) return json({ error: "Rate limit identity unavailable" }, 503);
  const { data: allowed, error: rateError } = await admin.rpc("consume_telemetry_rate_limit", {
    p_key_hash: hashedAddress,
  });
  if (rateError) {
    console.error("telemetry rate limit unavailable");
    return json({ error: "Telemetry unavailable" }, 503);
  }
  if (allowed !== true) return json({ error: "Rate limit exceeded" }, 429);

  let rawBody: string | null;
  try {
    rawBody = await readBoundedBody(req);
  } catch (error) {
    if (error instanceof RangeError) return json({ error: "Payload too large" }, 413);
    return json({ error: "Invalid request body" }, 400);
  }
  if (rawBody === null) return json({ error: "Invalid request body" }, 400);

  let body: any;
  try { body = JSON.parse(rawBody); } catch { return json({ error: "Invalid JSON" }, 400); }
  if (!body || typeof body !== "object" || Array.isArray(body) || !channels.has(body.channel) ||
      !boundedString(body.appVersion, 32) || !boundedString(body.buildNumber, 32) ||
      !boundedString(body.gitSHA, 16) || !Array.isArray(body.events) ||
      body.events.length < 1 || body.events.length > 20) {
    return json({ error: "Invalid telemetry envelope" }, 400);
  }

  const now = Date.now();
  const rows = [];
  for (const event of body.events) {
    if (!event || typeof event !== "object" || Array.isArray(event) || !kinds.has(event.kind) ||
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

  const { error } = await admin.from("app_telemetry_events").insert(rows);
  if (error) {
    // Do not log payloads, event names, keys, or request headers.
    console.error("telemetry insert failed");
    return json({ error: "Telemetry unavailable" }, 503);
  }
  return json({ accepted: rows.length }, 202);
});
