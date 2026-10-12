# QA pass on key flows (beta-promotion gate)

The `KeyFlowsQATests` suite runs when a `Build IPA` workflow is manually dispatched with `run_tests=true`, or when the pushed commit message contains `[run tests]`. It is **not run on every ordinary `main` push**: those builds still run the IPA smoke checks and publish `latest-build`. For a validated beta promotion, the unit tests, all eight key flows, every UI-test shard, and backend E2E must pass; only then does CI publish `latest-beta`. The flow → pass/fail table goes into the job summary and release notes (`scripts/qa-summary.py`). The UI-test launch flag enables beta diagnostics for automation; a production build must not show the Beta banner or Settings › Beta testing entry. Validate channel gating separately with `TierA` and `Production`/empty channel builds.

| # | Flow | Automated test | What it checks |
|---|---|---|---|
| 1 | Add recipe from URL | `testQA1_AddFromURL` | JSON-LD fixture → "Imported from page data" badge; Instagram caption fixture → card; hidden caption → friendly message + switch to Prompt |
| 2 | Add from photo | `testQA2_AddFromPhoto` | text screenshot via real Vision OCR; text-free food photo → "Guessed from photo" or the friendly message, never the old OCR error |
| 3 | Generate and edit | `testQA3_GenerateAndEdit` | edit title + cuisine on the review step |
| 4 | Save | `testQA4_Save` | lands in the library |
| 5 | Share | `testQA5_Share` | "Share link" and "Share as text" both open the share sheet (one link per share) |
| 6 | Open shared recipe | `testQA6_OpenShared` | `ate://recipe/<slug>` opens + saves; expired slug; unknown route → not found |
| 7 | Sync account | `testQA7_SyncAccount` | sign in, edit, sync, then a second launch with an empty local store pulls the edit (persistent mock server) |
| 8 | Timers | `testQA8_Timers` | start, pause (doesn't move), resume, leave cook mode → timer bar, finish → chime + haptic fired, Live Activity requested (test hook `qa.probe`) |

Real-server staging sync via curl runs only if staging secrets are configured (not yet — PRD v1.3 action 7).

## Manual on-device checklist (do before handing a build to testers)

Device: ______ iOS: ______ Build: ______ Apple Intelligence on? ☐

1. **URL** ☐ a recipe blog link imports with "Imported from page data" ☐ an Instagram reel with a caption imports ☐ one without shows "paste the caption into Prompt" and the button switches tabs ☐ a dead site fails in ≤ 10 s with a clear message
2. **Photo** ☐ a screenshot of a recipe imports ☐ a camera photo of a plate gives "Guessed from photo" ☐ a non-food photo gives the friendly message
3. **Generate & edit** ☐ a prompt gives a "Made with Apple Intelligence" card ☐ edit title, an ingredient, a step and cuisine before saving
4. **Save** ☐ appears in the library ☐ survives force-quit and relaunch
5. **Share** ☐ Share link sends exactly one link ☐ Share as text reads well in WhatsApp/iMessage
6. **Open shared** ☐ tapping `ate://recipe/<slug>` on a second iPhone opens the recipe ☐ an old/invalid link says expired
7. **Sync** ☐ sign up → confirmation email → link opens ate signed in ☐ magic link ☐ password reset ☐ edit on phone A, pull on phone B ☐ edit the same recipe on both offline, then sync: newest wins ☐ delete on A disappears on B ☐ sign out (keep) / sign in as a *different* account: the first account's recipes don't appear ☐ delete account
8. **Timers** ☐ start a step timer, lock the phone: Dynamic Island + Lock Screen count down ☐ pause/resume ☐ leave cook mode: timer bar shows above the tab bar ☐ finish: chime + haptic, notification if backgrounded
9. **Other device classes** ☐ an iPhone without Apple Intelligence (badges say Demo / page data) ☐ iOS 18 device if available ☐ VoiceOver pass on Library, Add, Cook ☐ largest Dynamic Type
