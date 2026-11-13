# Outbound endpoint coverage

Source:841c14ee, iPhone + Watch + App Clip + edge source. No live requests performed.

57 request variants included. This is source-route coverage, NOT100% behavior/auth/permission/device coverage.

| Endpoint/method | In collection | Request or reason | Source |
| --- | --- | --- | --- |
| POST `/auth/v1/signup?redirect_to=ate%3A%2F%2Fauth-callback` | yes | Sign up (sends email) | Ate/Services/Auth.swift (SupabaseAuth) |
| POST `/auth/v1/token?grant_type=password` | yes | Password sign in | Ate/Services/Auth.swift (SupabaseAuth) |
| POST `/auth/v1/token?grant_type=refresh_token` | yes | Refresh token | Ate/Services/Auth.swift (SupabaseAuth); AteWatch/WatchStore.swift |
| POST `/auth/v1/otp?redirect_to=ate%3A%2F%2Fauth-callback` | yes | Magic email link (save verifier locally for later PKCE exchange) | Ate/Services/Auth.swift (SupabaseAuth) |
| POST `/auth/v1/resend?redirect_to=ate%3A%2F%2Fauth-callback` | yes | Resend signup email | Ate/Services/Auth.swift (SupabaseAuth) |
| POST `/auth/v1/recover?redirect_to=ate%3A%2F%2Fauth-callback` | yes | Recovery email (save verifier locally) | Ate/Services/Auth.swift (SupabaseAuth) |
| POST `/auth/v1/token?grant_type=pkce` | yes | PKCE exchange after email callback | Ate/Services/Auth.swift (SupabaseAuth) |
| GET `/auth/v1/user` | yes | Read authenticated user | Ate/Services/Auth.swift (SupabaseAuth) |
| PUT `/auth/v1/user` | yes | Update password (synthetic account only) | Ate/Services/Auth.swift (SupabaseAuth) |
| POST `/auth/v1/otp` | yes | Watch request email code | Shared/Watch/WatchLogic.swift (WatchAuthRequests.otp) |
| POST `/auth/v1/verify` | yes | Watch verify email code | Shared/Watch/WatchLogic.swift (WatchAuthRequests.verify) |
| POST `/auth/v1/logout` | yes | Logout (invalidates session) | Ate/Services/Auth.swift (SupabaseAuth) |
| GET `/rest/v1/user_recipes?select=user_id,kind,id,data,updated_at,deleted&user_id=eq.{{user_id}}` | yes | Recipe and shopping rows (iPhone) | Ate/Services/Sync.swift (SupabaseSync.pull) |
| GET `/rest/v1/user_recipes?select=kind,id,data,updated_at,deleted` | yes | Watch rows | Shared/Watch/WatchLogic.swift (WatchAuthRequests.rowsURL) |
| GET `/rest/v1/qa_results?select=item_id,status,note,build,ts,commit_sha,run_id,run_url&source=eq.ci&user_id=eq.{{user_id}}&order=ts.desc&build=eq.{{qa_build}}&commit_sha=eq.{{commit_sha}}&run_id=eq.{{run_id}}&limit=500` | yes | CI results bound to owner/build/source | Ate/Services/BetaQA.swift (CIStatus.refresh) |
| POST `/rest/v1/rpc/account_data_snapshot` | yes | Atomic account snapshot | Ate/Store/AccountDataResetService.swift (snapshot) |
| POST `/rest/v1/user_recipes?on_conflict=user_id,kind,id` | yes | Legacy recipe direct write must be fenced after v6 | Ate/Services/Sync.swift; AteWatch/WatchStore.swift; v6 migration revokes writes |
| POST `/rest/v1/rpc/put_user_recipe` | yes | Generation-aware recipe put | Ate/Store/AccountDataResetService.swift (putRecipe) |
| POST `/rest/v1/user_recipes?on_conflict=user_id,kind,id` | yes | Legacy shopping direct write must be fenced after v6 | Ate/Services/Sync.swift; AteWatch/WatchStore.swift; v6 migration revokes writes |
| POST `/rest/v1/rpc/put_user_recipe` | yes | Generation-aware shopping put | Ate/Store/AccountDataResetService.swift (putRecipe) |
| POST `/rest/v1/qa_results?on_conflict=user_id,build,item_id,source` | yes | Upload synthetic QA device result | Ate/Services/BetaQA.swift (BetaQA.upload): untested synthetic transport fixture, intentionally not uploadable qualification evidence |
| POST `/rest/v1/rpc/account_data_snapshot` | yes | 01 Capture snapshot before reset | AccountDataResetService.snapshot |
| POST `/rest/v1/rpc/clear_account_data` | yes | 02 Clear synthetic account data | AccountDataResetService.clearAccount |
| POST `/rest/v1/rpc/clear_account_data` | yes | 03 Retry SAME reset UUID and expected generation | clear_account_data idempotence |
| POST `/rest/v1/rpc/put_user_recipe` | yes | 04 Put retained row at new generation | put_user_recipe current epoch |
| POST `/rest/v1/rpc/put_user_recipe` | yes | 05 Stale put must return PT409 | put_user_recipe stale epoch |
| POST `/rest/v1/rpc/clear_account_data` | yes | 06 Different reset UUID with stale epoch must conflict | clear_account_data stale expected epoch |
| POST `/rest/v1/rpc/clear_account_data` | yes | 07 Same UUID with wrong expected epoch must conflict | clear_account_data wrong retry |
| POST `/rest/v1/rpc/account_data_snapshot` | yes | 08 Verify no mutation after conflicts | account_data_snapshot conflict reconciliation |
| POST `/rest/v1/rpc/account_data_snapshot` | yes | account_data_snapshot anon denied | v6 authenticated-only EXECUTE; PostgREST anon42501→HTTP401 |
| POST `/rest/v1/rpc/put_user_recipe` | yes | put_user_recipe anon denied | v6 authenticated-only EXECUTE; PostgREST anon42501→HTTP401 |
| POST `/rest/v1/rpc/clear_account_data` | yes | clear_account_data anon denied | v6 authenticated-only EXECUTE; PostgREST anon42501→HTTP401 |
| POST `/functions/v1/publish-recipe` | yes | Publish synthetic shared recipe | Ate/Services/BackendService.swift (SupabaseBackend.publish); supabase/functions/publish-recipe |
| GET `/functions/v1/get-shared-recipe?slug={{share_slug}}` | yes | Read shared recipe (iPhone and Clip) | SupabaseBackend.fetchShared; AteClip/SharedRecipeClient.swift |
| GET `/functions/v1/get-shared-recipe?slug=!` | yes | Shared recipe invalid slug | supabase/functions/get-shared-recipe |
| POST `/functions/v1/parse-recipe` | yes | AI parse prompt (not implemented in repo) | SupabaseBackend.parseRecipe; no supabase/functions/parse-recipe implementation. Currently unavailable; opt-in only after staging implementation exists. |
| POST `/functions/v1/parse-recipe` | yes | AI parse url (not implemented in repo) | SupabaseBackend.parseRecipe; no supabase/functions/parse-recipe implementation. Currently unavailable; opt-in only after staging implementation exists. |
| POST `/functions/v1/parse-recipe` | yes | AI parse image (not implemented in repo) | SupabaseBackend.parseRecipe; no supabase/functions/parse-recipe implementation. Currently unavailable; opt-in only after staging implementation exists. |
| POST `/functions/v1/parse-recipe` | yes | AI parse rewrite (not implemented in repo) | SupabaseBackend.parseRecipe; no supabase/functions/parse-recipe implementation. Currently unavailable; opt-in only after staging implementation exists. |
| POST `/functions/v1/telemetry` | yes | Send category-only synthetic telemetry | Ate/Services/TelemetryClient.swift; supabase/functions/telemetry |
| POST `/functions/v1/beta-feedback` | yes | Send synthetic beta feedback | Ate/Services/BetaFeedbackService.swift; supabase/functions/beta-feedback |
| POST `/functions/v1/delete-account` | yes | Delete synthetic test account (including shared recipes) | Ate/Services/Auth.swift (deleteAccount); supabase/functions/delete-account |
| GET `{{recipe_page_url}}` | yes | Import recipe HTML | OnDeviceBackend.fetchHTML |
| GET `{{social_page_url}}` | yes | Social caption HTML | OnDeviceBackend.fetchSocialCaption |
| GET `{{cover_page_url}}` | yes | Cover source page | CoverStore.findPageImage |
| GET `{{cover_image_url}}` | yes | Cover image bytes | CoverStore.download |
| GET `https://www.tiktok.com/oembed?url={{encoded_social_url}}` | yes | TikTok oEmbed | SocialLinks.oEmbedURL; CoverStore.findPageImage |
| GET `https://www.youtube.com/oembed?format=json&url={{encoded_social_url}}` | yes | YouTube oEmbed | SocialLinks.oEmbedURL; CoverStore.findPageImage |
| GET `{{privacy_url}}` | yes | Privacy page | AuthSheet LegalWebView; AppConfig.privacyURL |
| GET `{{terms_url}}` | yes | Terms page | AuthSheet LegalWebView; AppConfig.termsURL |
| GET `{{share_page_url}}` | yes | Share landing page | ShareLinks.defaultTemplate; external browser share handoff |
| SDK `SDK-derived Sentry ingestion` | no | No raw endpoint fixture: DSN/envelope/session/crash mechanics are SDK-owned. In-app synthetic proof flow verifies privacy scrubbing; hand-written ingestion would bypass it. | Ate/Services/SentryBootstrap.swift |
| local framework `Foundation Models / Vision / Image Playground` | no | No REST endpoint or remote AI provider in app source; device/native tests required. | Ate/Services/OnDeviceBackend.swift; CoverStore.swift |
| none `Supabase Storage` | no | No storage HTTP call in iPhone/Watch/Clip source; covers are local files or external image GET. | Repository outbound inventory |
| DELETE server-only `GoTrue admin DELETE /auth/v1/admin/users/{id}` | no | Server-only service-role call behind delete-account; never put service-role credentials in client Postman environment. | supabase/functions/delete-account/index.ts |
| GET server-internal `GoTrue authenticated user lookup` | no | Already exercised indirectly through edge API; no separate server service-role identity fixture. | supabase/functions/publish-recipe/index.ts; delete-account/index.ts |
| GET/POST/DELETE server-only `shared_recipes SELECT/INSERT/DELETE` | no | Covered via edge entry points; table listing is intentionally not a public app API. | supabase/functions/get-shared-recipe; publish-recipe; delete-account |
| POST server-only `beta_feedback INSERT and consume_beta_feedback_rate_limit RPC` | no | Covered via edge; admin/rate-limit bypass templates excluded. | supabase/functions/beta-feedback/index.ts |
| POST server-only `app_telemetry_events INSERT and consume_telemetry_rate_limit RPC` | no | Covered via edge; admin/rate-limit bypass templates excluded. | supabase/functions/telemetry/index.ts |
| local framework `HealthKit / WatchConnectivity / WidgetKit / notifications / Spotlight / App Intents` | no | No Postman-replayable endpoint. Apple service traffic is OS-controlled and not an app endpoint contract. | Ate/Services; AteWatch; Shared |
| dynamic `arbitrary redirects / CDN URLs / linked subresources` | no | Parameterized initial requests included; cannot enumerate every external URL or simulate browser cookie/captcha/JS behavior. | CoverStore; OnDeviceBackend; AuthSheet WKWebView |
| fixture only `fixtures.ate.test and example URLs in tests/checklists` | no | Mock/test data, not live endpoints; no external request generated. | Ate/Logic/QAFixtures.swift; test targets |
| POST `/functions/v1/get-shared-recipe` | yes | Shared recipe POST alternate server contract | supabase/functions/get-shared-recipe/index.ts, alternate supported method (not called by app) |
| OPTIONS `/functions/v1/publish-recipe` | yes | OPTIONS publish-recipe | supabase/functions/publish-recipe/index.ts CORS preflight |
| OPTIONS `/functions/v1/get-shared-recipe` | yes | OPTIONS get-shared-recipe | supabase/functions/get-shared-recipe/index.ts CORS preflight |
| OPTIONS `/functions/v1/delete-account` | yes | OPTIONS delete-account | supabase/functions/delete-account/index.ts CORS preflight |
| OPTIONS `/functions/v1/telemetry` | yes | OPTIONS telemetry | supabase/functions/telemetry/index.ts CORS preflight |
| OPTIONS `/functions/v1/beta-feedback` | yes | OPTIONS beta-feedback | supabase/functions/beta-feedback/index.ts CORS preflight |
