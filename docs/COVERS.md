# Recipe cover images

**Priority** (`CoverLogic.pick`): 1. your own photo/screenshot (Image tab, camera, or "Change photo" on review) → cropped 4:3, ≤1200 px, JPEG 0.8 · 2. the page's `og:image` / `twitter:image` / JSON-LD `image`, or the YouTube/TikTok oEmbed `thumbnail_url` (Instagram: og:image) · 3. on-device Image Playground (`ImageCreator`, iOS 18.4+, Apple Intelligence devices; prompt/text recipes, or "Generate" on review) · 4. the branded tile (warm brand gradient by cuisine/main ingredient, Fraunces initial, faint SF Symbol).

**Storage:** `RecipeCard.coverImage` is a file name in `Covers/` (App Group, else Application Support). `imageURL` holds the https remote URL if any.
`"none"` means the user removed the cover.

**Sync:** image bytes are **not** synced. Only `imageURL` (and the file name, which other devices ignore when the file is missing) travel in the jsonb. A user photo stays on the phone that took it; other devices show the tile (or re-fetch the page image).

**Share:** only an https `imageURL` is sent to `publish-recipe`; it is stored inside the `card` jsonb (and the existing `image_url` column), so no migration. The web page (`ate-legal/r/`) shows it as the hero and og:image.
*`publish-recipe` changes (https-only, optional top-level `image_url`) need a `supabase functions deploy publish-recipe`; the live function already stores `card.imageURL`.*

**Backfill:** existing recipes show the tile right away; when a row appears, an https `imageURL` is downloaded or the `sourceURL` page is checked for og:image (once per launch).
