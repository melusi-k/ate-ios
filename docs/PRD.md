# Ate — Product Requirements Document (native iOS / SwiftUI rebuild)

Source: Lovable project **"Ate"** (id `88fe6d64-6eec-4bcb-9f12-7ad3a0c02bbf`), reviewed read-only on 2026-10-10.
Web stack today: TanStack Start (React) + Tailwind/shadcn, localStorage persistence, Supabase (one table), Lovable AI Gateway (Gemini). Published at `recipe-transform-ai.lovable.app`.

---

## 1. Product overview
**ate** (always lowercase in branding) is an AI recipe library. Users paste a **link**, upload a **screenshot**, or type a **prompt**, and ate produces a clean, editable **recipe card** (title, description, servings, time, tags, ingredients, steps with optional timers). Cards are saved **on-device**. From a card the user can scale servings, rewrite it with AI ("make this vegan"), add ingredients to a merged **shopping list**, share a public read-only link, and cook in a big-text **Cook mode** with step timers and alerts.

Tagline: "Turn any link, screenshot or idea into a clean recipe card you can cook from."

### Goals
- Paste-to-card in seconds; user always reviews before saving.
- Offline-first: library, shopping list and cook mode work with no network.
- Privacy: "Private mode" disables all AI calls.

### Non-goals (v1 iOS)
- Accounts/sign-in, cloud sync of the library (web has none).
- Android / iPad-specific layouts (iPhone first; iPad may run scaled).

## 2. Target users
- Home cooks who save recipes from TikTok/Instagram/blogs and want them de-cluttered.
- People who screenshot recipes and lose them in the camera roll.
- Weekly meal planners who need a combined grocery list.
- Hands-busy cooks who want large text and timers at the stove.

## 3. Information architecture & navigation

```
NavigationStack (root = Library)
├── Library  "/"
│   ├── toolbar → Shopping list "/shopping"
│   ├── toolbar → Settings "/settings"
│   ├── row tap → Recipe detail "/recipe/:id"
│   │      ├── Edit (inline toggle on same screen)
│   │      ├── Share → system share sheet (+ public link /r/:slug)
│   │      ├── Delete → back to Library
│   │      └── Cook mode "/cook/:id" (full-screen cover recommended)
│   └── FAB "Add recipe" → Add Recipe sheet (modal)
│          └── Save → push Recipe detail of new card
└── Shared recipe "/r/:slug"  (opened via Universal Link / deep link)
       └── "Save to my library" → Recipe detail of the copy
404 / error states: "Page not found", "Recipe not found", "Nothing to cook here", "This recipe link has expired".
```
iOS: use a single `NavigationStack` with a `Route` enum (`.recipe(id)`, `.cook(id)`, `.shopping`, `.settings`, `.shared(slug)`). Back buttons in web are labelled "Library" / "Exit" / "Open ate" — use these as back titles. Handle `ate://r/<slug>` and `https://recipe-transform-ai.lovable.app/r/<slug>` via `.onOpenURL`.

Toasts (sonner, top-center) → implement a lightweight top toast/banner overlay (success / error).

## 4. Screens

### 4.1 Library (Home) — `/`
**Purpose:** browse and search saved recipes; entry to everything else.
**Layout (max width ~672pt, 16pt side padding, 32pt top, 112pt bottom for FAB):**
- Header row:
  - Left: logo image (`ate-logo.png`, 28×28) + wordmark "ate" (14pt bold, lowercase, letter-spacing 0.2em, primary color). Below: H1 "Your kitchen library" (36pt bold, Fraunces). Subtitle: "{n} recipe(s) saved on this device." (14pt, muted).
  - Right: two ghost icon buttons — ShoppingBasket (→ Shopping), Settings gear (→ Settings). SF Symbols: `basket`, `gearshape`.
- Search field: 48pt tall, fully rounded (capsule), leading magnifier icon, placeholder "Search chicken, pasta, vegan…". Filters case-insensitively across title + description + tags + ingredient names.
- List (12pt spacing) of **RecipeRow** cards (§5.2). Tap → Recipe detail.
- Empty state card (card-surface, centered, 56pt vertical padding): icon UtensilsCrossed (`fork.knife`, primary), title "Nothing saved yet" + "Paste a link or a screenshot and get a clean recipe card in seconds." If recipes exist but none match: "No matches" + "Try another ingredient or tag."
- Floating primary button bottom-center (56pt tall, capsule, 28pt h-padding, float shadow): "+ Add recipe" → presents Add Recipe sheet.
**Data:** all recipes (newest first — new cards are inserted at index 0).

### 4.2 Add Recipe sheet (modal, from Library)
**Purpose:** create a card via AI.
**State 1 — input:**
- Title "Add a recipe" (24pt Fraunces); description "ate turns a link, a screenshot or an idea into a clean recipe card."
- Segmented control, 3 tabs: **Link** (`link`), **Image** (`photo.badge.plus`), **Prompt** (`pencil.line`).
  - Link: text field, placeholder "https://tiktok.com/...", URL keyboard. (iOS: also accept share-extension / paste from clipboard.)
  - Image: dashed-border rounded (12pt) drop zone on muted/50 bg, 32pt padding: "Upload a recipe screenshot" / "Screenshot ready — tap to replace". Use `PhotosPicker` (+ camera optional). Preview image below, max 192pt tall, aspect-fill, rounded 12pt.
  - Prompt: 3-line text editor, placeholder "A quick weeknight miso salmon for two".
- Full-width large primary button: "✨ Generate recipe card"; loading: spinner + "Cooking up your card…" (disabled).
- Validation toasts: Private mode on → "Private mode is on — turn it off in Settings to use AI."; empty link → "Paste a recipe link first."; empty prompt → "Describe the dish first."; no image → "Upload a screenshot first."
**State 2 — review:**
- Title "Review your card"; description "Fix anything the AI got wrong, then save it to your library."
- Shows RecipeCardView (§5.1) or RecipeEditor (§5.3) when editing.
- Buttons row: **Save recipe** (primary, flex) → save, toast "Saved to your library", dismiss, push Recipe detail. **Edit/Preview** toggle (secondary). **Regenerate** (ghost, RefreshCw icon spins while loading).
- Closing the sheet resets all state. `sourceURL` = link when mode is Link.
- Sheet height ≤ 88% screen, scrollable → `.presentationDetents([.large])`.

### 4.3 Recipe detail — `/recipe/:id`
**Purpose:** read, scale, edit, rewrite, share, shop, cook.
- Top bar: back "← Library"; right icon buttons: Share (`square.and.arrow.up`), Edit (`pencil`, toggles edit mode), Delete (`trash`, destructive color) → delete immediately, toast "Recipe deleted", pop to Library. (iOS: add a confirmation dialog — recommended improvement.)
- **Edit mode:** card-surface (20pt padding) with RecipeEditor; every change saves immediately; full-width "Done" button exits edit.
- **View mode:**
  - Servings scaler: three capsule small buttons "x1 servings", "x2 servings", "x3 servings"; selected = primary, others = secondary. Factor multiplies quantities and displayed servings.
  - RecipeCardView with factor.
  - Secondary capsule full-width 48pt button "Add to shopping list" (`list.bullet` + plus) → merges scaled ingredients (source = recipe title), toast "Added to your shopping list".
  - "Ask ate" card: overline label (12–14pt bold uppercase, tracking widest, muted). Text field placeholder "Make this vegan" + primary icon button (sparkles / spinner). Submit on return. Calls AI rewrite, keeps id & createdAt, toast "Recipe updated"; errors shown as toast.
  - Floating bottom-center primary button "Cook mode" (`frying.pan`/chef hat icon) → Cook mode.
- Not found: "Recipe not found" + button "Back to library".
**Share flow:** build plain text (§7.4) for the current factor; call publish to get slug; url = `<host>/r/<slug>`; present `ShareLink`/`UIActivityViewController` with title, text, url. If publish fails, toast "Could not create a share link. Sharing the text instead." and share text only. Fallback copy to clipboard toast "Share link copied to clipboard" / "Recipe copied to clipboard".

### 4.4 Cook mode — `/cook/:id`
**Purpose:** hands-free, big-text, step-by-step cooking with timers.
- Full-screen, background **warm**, text warm-foreground, padding 20pt h / 24pt top / 32pt bottom. Keep screen awake (`isIdleTimerDisabled = true`).
- Top: ghost "← Exit" (→ Recipe detail); right "Step {i} of {n}" (14pt medium).
- Progress bar: 6pt tall, capsule track warm-foreground @15%, fill primary, width = (i+1)/n, animated.
- Center (vertically centered, flexible): step instruction, 30pt (34pt on larger) bold Fraunces, line-height snug.
- If step has `timeSeconds`: timer pill (card bg, rounded 16pt, 20×12 padding) with Timer icon (primary) and `m:ss` in 36pt bold monospaced digits; Play/Pause primary capsule button; Reset (`arrow.counterclockwise`) secondary capsule button. Timer resets when step changes. On first play: request notification permission and prime audio.
- On reaching 0: stop, fire `timerFinished("Step {i}", recipeTitle)` (§7.6).
- Bottom: "Back" secondary capsule (56pt, flex 1, disabled on first step); "Next step" primary capsule (flex 2, disabled on last step).
- Empty: "Nothing to cook here" + "Back to library".
- iOS timer must survive backgrounding: store end `Date`, schedule a local `UNNotification` at end time; cancel on pause/reset.
- Product description mentions **voice-controlled step navigation** (not implemented in web code). iOS stretch: `SFSpeechRecognizer` commands "next", "back", "start timer", "pause".

### 4.5 Shopping list — `/shopping`
**Purpose:** one merged grocery list across recipes.
- Back "← Library"; H1 "Shopping list" (30pt bold); subtitle "{pending} to buy · {done} in the basket" (second part only if done>0).
- Add row: capsule 48pt text field "Add something else…" + 48pt round primary "+" button; submit adds a manual item (qty 0, no unit).
- Empty state card: "Nothing on the list" / "Open a recipe and tap “Add to shopping list” — quantities merge automatically."
- List (8pt spacing) of card-surface rows (16×12 padding): checkbox (toggle done), label `"{qty unit} {name}"` (truncated; done = muted + strikethrough), optional caption = source recipe (12pt muted), ghost trash button. Pending items first, then done.
- Export card (when items exist): H2 "Export". Buttons: "Share / copy" (primary → share sheet with list text), "Copy text" (secondary, toast "Copied as text"), ".txt" and ".csv" (secondary → share a file `ate-shopping-list.txt` / `.csv` via share sheet / Files). Second row: ghost "✓ Clear ticked" (disabled if none done), ghost destructive "Clear all" (toast "List cleared").
- Data model supports aisles (Produce, Dairy, Meat & Fish, Pantry, Bakery, Frozen, Other) with keyword guessing (§7.3); web UI doesn't group yet — iOS optional: section by aisle.

### 4.6 Settings — `/settings`
- Back "← Library"; H1 "Settings".
- Card 1: **Private mode** toggle — "Keep everything local — no new AI generations, only your saved cards." (`onDeviceOnly`).
- Card 2: **Timer notifications** — "Choose how ate lets you know a cook-mode step timer has finished." Toggles:
  - Sound — "Play a chime when a timer ends." (default on)
  - Vibration — "Buzz your device (where supported)." (default on) → iOS haptics
  - Step-by-step alerts — "Show a system notification for each step." (default on; turning on requests notification permission)
  - Divider, **Quiet hours** — "Mute the chime during this window — vibration and alerts still work." (default off). When on: two time pickers "From" (default 22:00) and "Until" (07:00), side by side.
- Card 3: **Your data** — "Recipes are stored on this device only. Nothing is uploaded when you browse or cook." Buttons: "Export data" (secondary → share `ate-recipes.json`, pretty JSON array), "Import recipes" (secondary → `fileImporter` for .json; toast "Imported {n} recipe(s)" / "Library up to date" / error "That file isn't a ate export."), "Clear all" (ghost destructive, toast "Library cleared"; iOS: add confirmation).
- Settings model also has `units: metric|imperial` (default metric) — not exposed in web UI; iOS may add a "Units" segmented picker.

### 4.7 Shared recipe — `/r/:slug`
- Loads row from Supabase `shared_recipes` by slug (public read).
- Back "← Open ate"; RecipeCardView (factor 1); floating primary "Save to my library" (`bookmark` + plus) → copy with new id & createdAt, toast "Saved to your library", navigate to Recipe detail.
- Missing/error: "This recipe link has expired" / "The shared recipe could not be found." + "Open ate".

### 4.8 System states
- 404: "404" (72pt bold), "Page not found", "The page you're looking for doesn't exist or has been moved.", "Go home".
- Error: "This page didn't load", "Something went wrong on our end. You can try refreshing or head back home.", buttons "Try again" / "Go home".

## 5. Shared components

### 5.1 RecipeCardView (props: recipe, factor=1, units=metric)
- card-surface, clipped.
- Header block, bg **warm**, padding 20×24: title 24pt bold (warm-fg); description 14pt warm-fg@80%; meta row: clock "{min} min" (if any), people "{servings×factor} servings"; tags as outline capsule badges.
- Body (padding 20, sections 24 apart):
  - "INGREDIENTS" overline. Rows: fixed 96pt-wide amount column (medium, tabular digits, `formatAmount` after unit conversion) + name, and " — notes" in muted. Each row bottom border (border@60%), 8pt spacing.
  - "STEPS" overline. Numbered rows: 24pt primary circle with white number (12pt bold) + instruction (temperatures converted) + " ({round(sec/60)} min)" muted if timed.

### 5.2 RecipeRowView
card-surface, 16pt padding, 16pt gap, press scale 0.99. Thumbnail 56×56 rounded 16pt (imageURL if http(s), else a generated placeholder seeded from title+tags — iOS: deterministic gradient/emoji tile). Title 18pt semibold single line; description 14pt muted 2 lines; meta 12pt muted: clock min, people servings, first 2 tags as secondary capsule badges.

### 5.3 RecipeEditor (controlled; parent persists)
Fields: Title; Description (2 lines); 2-col Servings (int ≥1) and Total minutes; Tags (comma separated). Ingredients section header with "+ Add" (secondary small): each row = Quantity (80pt number), Unit (80pt, "unit"), Name ("ingredient", flex), trash; Notes full width ("notes (e.g. finely chopped)"). Steps section with "+ Add": instruction (2-line editor), seconds (96pt number, "sec"), trash (re-numbers orders).

## 6. Data models (Swift)
```swift
struct Ingredient: Codable, Hashable { var name: String; var quantity: Double; var unit: String; var notes: String? }
struct Step: Codable, Hashable { var order: Int; var instruction: String; var timeSeconds: Int? }
struct RecipeCard: Codable, Identifiable, Hashable {
  var id: String            // UUID string
  var title: String         // default "Untitled recipe"
  var description: String?
  var servings: Int         // >=1, default 2
  var timeMinutes: Int?
  var tags: [String]
  var ingredients: [Ingredient]
  var steps: [Step]         // order re-numbered 1..n on normalize
  var imageURL: String?
  var sourceURL: String?
  var createdAt: Double     // ms since epoch (keep for JSON compatibility with web export)
}
enum Aisle: String, Codable, CaseIterable { case produce="Produce", dairy="Dairy", meatFish="Meat & Fish", pantry="Pantry", bakery="Bakery", frozen="Frozen", other="Other" }
struct ShoppingItem: Codable, Identifiable { var id: String; var name: String; var quantity: Double; var unit: String; var done: Bool; var from: String?; var sources: [String]?; var notes: String?; var aisle: Aisle? }
struct Settings: Codable { var onDeviceOnly = false; var units: UnitSystem = .metric }
enum UnitSystem: String, Codable { case metric, imperial }
struct TimerPrefs: Codable { var sound = true; var vibration = true; var stepAlerts = true; var quietHours = false; var quietStart = "22:00"; var quietEnd = "07:00" }
```
`normalizeCard`: trim title (fallback "Untitled recipe"), servings = max(1, value or 2), drop empty tags, coerce numbers, renumber steps, defaults for nil.
**Persistence:** web uses localStorage keys `feedme.recipes.v1`, `feedme.settings.v1`, `feedme.shopping.v1`, `feedme.timerprefs.v1`. iOS: JSON files in Application Support (or SwiftData) behind an `@Observable` store; settings/timer prefs in `UserDefaults`/`@AppStorage`. Import/export JSON must be compatible with the web format (array of RecipeCard). Import skips cards with no ingredients and no steps; replaces same-id cards; counts only new ones.

## 7. Business logic to port
### 7.1 Scaling
`quantity × factor`, rounded to 2 decimals; servings shown = round(servings × factor).
### 7.2 Units (`units.ts`)
- Alias table → canonical: g, kg, ml, l, oz, lb, fl oz, cup, tsp, tbsp (with plurals/long names).
- `niceRound`: ≥100 → nearest 5; ≥10 → integer; ≥1 → nearest 0.25; else 2 dp.
- Imperial: g→oz (→lb if ≥16 oz), kg→lb (×2.20462), ml/l→cup if ≥240 ml else fl oz (÷29.5735). Metric: oz/lb→g (→kg if ≥1000), fl oz→ml, cup→ml (×240). Others pass through.
- Temps in text: `(\d{2,3})\s*(°|º|degrees)\s*([CF])` → convert and round to nearest 5.
- `formatUnit`: hide pcs/pc/x/whole/unit(s)/item(s); pluralise clove, piece, can, slice, cup, pinch, bunch, sprig, stick, handful, head, leaf→leaves, tin, packet, jar, fillet, stalk, knob, dash, bottle, bag, sheet, wedge when qty>1 or 0.
- `formatAmount` = "{qty} {unit}" (qty empty when 0).
- `findDurations` regex (e.g. "10 minutes", "1 hr 15 min", "8-10 mins" → upper bound) — available for auto-detecting step timers.
### 7.3 Shopping merge
Merge into an existing **not-done** item when singularised names match and unit families match (mass: g,kg,oz,lb; volume: ml,l,tsp,tbsp,cup,fl oz; count: "",pcs,piece,x,whole; else same unit label). Same unit → add. Different units in a family → convert to base, output g/kg or ml/l (≥1000 → kg/l). Keep the longer name, append source recipe to `sources`, concat notes with "; ". Aisle guessing via keyword regexes (Frozen, Meat & Fish, Dairy, Bakery, Produce, Pantry checked in that order, else Other).
Text export: `ate — shopping list\n\n[ ] 300 g flour (notes)\n[x] …`. CSV header: `item,quantity,unit,notes,aisle,recipe,done`, strings quoted.
### 7.4 Recipe as text (share)
Title; description; "{servings} servings · {min} min"; blank; "Ingredients"; "- {amount} {name} (notes)"; blank; "Steps"; "1. …"; optional "Source: url"; optional share url.
### 7.5 AI parsing (`parseRecipe`)
Input `{mode: url|image|prompt|rewrite, text?, imageDataUrl?, currentRecipe?}` → `{card, source: structured|ai}`.
- url: fetch page (UA "AteBot/1.0", 8s timeout, 400 KB). If schema.org `Recipe` JSON-LD found (incl. `@graph`) → map directly, **no AI call**. Else send stripped page text (≤3500 chars) to AI.
- prompt: "Recipe card for: {text≤500}". image: text + image_url. rewrite: `Rewrite per "{ask}":\n{recipe JSON without id/createdAt/imageURL/sourceURL}`.
- Model chain: `google/gemini-3.6-flash` then `google/gemini-3.1-pro-preview` via `https://ai.gateway.lovable.dev/v1/chat/completions`, `response_format: json_object`, `max_tokens 1600`, with system prompt:
  > Recipe parser. Reply with ONLY minified JSON: {"title":s,"description":s,"servings":i,"timeMinutes":i,"tags":[s],"ingredients":[{"name":s,"quantity":n,"unit":s,"notes":s}],"steps":[{"order":i,"instruction":s,"timeSeconds":i|null}]} Numeric quantities, short units (g,ml,tbsp,cloves,pcs). timeSeconds only for waiting/cooking steps. Keep description under 20 words, steps concise. No prose, no fences.
- Robust JSON extraction with truncation repair. Errors: 429 "Rate limit reached — try again in a moment."; 402 "AI credits exhausted. Add credits to keep cooking."; fallback "AI returned an unreadable recipe. Try again."
- **iOS architecture:** the API key must NOT ship in the app. Options: (a) call the existing published web server function / a Supabase Edge Function `parse-recipe` that wraps this logic (recommended); (b) on-device: Vision `VNRecognizeTextRequest` OCR for screenshots + Apple Foundation Models (iOS 26) for structuring, falling back to the server. The product description explicitly cites "on-device AI and Vision OCR", so (b) is the intended direction with (a) as fallback.
### 7.6 Timer finished
Read prefs; quiet = within quiet window (handles overnight). Sound && !quiet → chime (3 sine tones: 784 Hz, 784 Hz, 1046 Hz at 0/0.28/0.56s) — iOS: bundled chime via AVAudioPlayer / notification sound. Vibration → `UINotificationFeedbackGenerator` / haptic pattern. Step alerts → local notification title "Step {i} is done", body recipe title (time-sensitive interruption level).

## 8. Backend / integrations
- **Supabase** (project from `.env`; URL + publishable key). Table:
```sql
create table public.shared_recipes (
  slug text primary key, title text not null, description text, image_url text,
  card jsonb not null, created_at timestamptz not null default now());
-- RLS: SELECT for anon & authenticated (USING true). Inserts only via service role.
```
- Publish: server (service role) inserts `{slug: 8-char base36, title, description, image_url, card}`; validation limits: title ≤200, description ≤1000, servings 1–200, tags ≤20 (≤60 chars), ingredients ≤100, steps ≤100, instruction ≤2000, urls ≤2000. iOS needs a server endpoint for this (Edge Function `publish-recipe`) since anon cannot insert. Read: iOS can query directly with `supabase-swift` + publishable key: `from("shared_recipes").select("slug,title,description,image_url,card").eq("slug", s).maybeSingle()`.
- Share URLs: `https://recipe-transform-ai.lovable.app/r/<slug>` (add Associated Domains for Universal Links later).
- Lovable AI Gateway (server-side only) — see §7.5.
- No auth, no analytics beyond Lovable error reporting (iOS: none / optional crash reporting).

## 9. Visual design
### 9.1 Colors (OKLCH source → sRGB hex approx)
| Token | Light | Dark |
|---|---|---|
| background | `#FCF7ED` (0.977 0.014 84) | `#1A120C` |
| foreground | `#311F16` | `#F3EEE4` |
| card / popover | `#FFFDF7` | `#271D16` |
| primary (terracotta) | `#C95028` (0.585 0.163 38) | `#E77140` |
| primary-foreground | `#FEFAF1` | `#190F0A` |
| secondary | `#F3EAD7` | `#352820` |
| secondary-foreground | `#442C21` | `#F3EEE4` |
| muted | `#F3ECDF` | `#352820` |
| muted-foreground | `#7B675B` | `#ADA397` |
| accent (herb green) | `#4E7F50` | `#5E9660` |
| warm (cook mode / card header) | `#F5E2C0` | `#453421` |
| warm-foreground | `#512E1A` | `#EFE3CF` |
| destructive | `#CC2827` | `#FF6467` |
| border / input | `#E6DDCE` | white @10% / 15% |
| ring | = primary | — |
Theme/status color: `#E2622A`. Implement as an Asset Catalog color set per token with light/dark variants. Default to system appearance.

### 9.2 Typography
- Display (h1–h3, sheet titles, cook-mode step): **Fraunces** (opsz 9–144, weights 500/700), tracking −0.01em. Bundle the font (OFL).
- Body/UI: **DM Sans** 400/500/700. Bundle (OFL).
- Scale used: 36 (library h1), 30 (page h1, cook step), 24 (card title / sheet title), 20 (empty-state h2), 18 (row title, section h2), 16 (base / toggle labels), 14 (body small), 12 (captions, badges). Overlines: bold uppercase, wide tracking (~0.1em). Numbers in amounts/timers: monospaced digits.
### 9.3 Shape, elevation, spacing
- Base radius 16pt (`--radius: 1rem`); sm 12, md 14, lg 16, xl 20, 2xl 24. **card-surface** = card bg + 1pt border + radius 20 + shadow-card (`0 1 2 rgba(brown,0.06)` + `0 12 30 −18 rgba(brown,0.35)`).
- Float shadow on FABs: y 10, blur 30, terracotta @45%.
- Buttons: primary (filled primary), secondary (filled secondary), ghost (transparent), outline; sizes sm/default/lg/icon; many are capsule (`rounded-full`).
- Content max width ~672pt; page padding 16pt; FAB clearance 112pt.
### 9.4 Iconography (lucide → SF Symbols)
Plus→`plus`, Search→`magnifyingglass`, Settings→`gearshape`, ShoppingBasket→`basket`, UtensilsCrossed→`fork.knife`, ArrowLeft→chevron back, ChefHat→`frying.pan`, ListPlus→`text.badge.plus`, Loader2→ProgressView, Pencil→`pencil`, Share2→`square.and.arrow.up`, Sparkles→`sparkles`, Trash2→`trash`, Pause/Play→`pause.fill`/`play.fill`, RotateCcw→`arrow.counterclockwise`, Timer→`timer`, Check→`checkmark`, Copy→`doc.on.doc`, Download→`arrow.down.doc`, Upload→`square.and.arrow.down`, Clock→`clock`, Users→`person.2`, BookmarkPlus→`bookmark`, Link2→`link`, ImagePlus→`photo.badge.plus`, PencilLine→`pencil.line`, RefreshCw→`arrow.clockwise`.
### 9.5 Assets
`src/assets/ate-logo.png` (1024², app logo), `public/icon-192.png`, `icon-512.png` (app icon source), `og-cover.png` (share fallback image). Download from the Lovable project for the asset catalog.

## 10. iOS-specific requirements
- iOS 17+ (iOS 26 for Foundation Models path), SwiftUI, Swift Concurrency, `@Observable` stores.
- Permissions: Photo library (add-image), Notifications, optional Camera, Speech & Microphone (voice cook mode).
- Share extension (stretch): "Save to ate" from Safari/TikTok/Photos → opens Add sheet prefilled.
- Offline: everything except AI generation, rewrite, publish and opening shared links.
- Accessibility: Dynamic Type, VoiceOver labels matching web aria-labels ("Shopping list", "Settings", "Share recipe", "Edit", "Delete", "Remove {item}", etc.), 44pt hit targets.

## 11. Acceptance checklist (per screen)
- [ ] Library: search filters live; empty/no-match states; FAB opens sheet.
- [ ] Add sheet: 3 modes, validation toasts, private-mode block, review/edit/regenerate/save.
- [ ] Recipe detail: x1/x2/x3 scaling, edit autosave, Ask ate rewrite, share link, add to list, delete, cook.
- [ ] Cook mode: progress, timers with background notification, back/next bounds, screen stays awake.
- [ ] Shopping: merge logic, manual add, toggle, remove, share/copy/txt/csv, clear ticked/all.
- [ ] Settings: private mode, 4 timer toggles + quiet hours pickers, export/import/clear.
- [ ] Shared recipe: deep link load, expired state, save copy.
