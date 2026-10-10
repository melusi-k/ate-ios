# Recipe cover images

**Priority** (`CoverLogic.pick`): 1. your own photo/screenshot (Image tab, camera, or "Change photo" on review) → cropped 4:3, ≤1200 px, JPEG 0.8 · 2. the page's `og:image` / `twitter:image` / JSON-LD `image`, or the YouTube/TikTok oEmbed `thumbnail_url` (Instagram: og:image) · 3. on-device Image Playground (`ImageCreator`, iOS 18.4+, Apple Intelligence devices): tried automatically, once per recipe, for **any** recipe whose web image path came up empty, plus **Generate cover** on review and in the recipe … menu · 4. the designed tile (plate + dish name).

**Widgets:** the Tonight's pick and Favourites widgets read the same `Covers/` files from the App Group (downsampled to 360 px in the extension); without the App Group they show the tile.

**Storage:** `RecipeCard.coverImage` is a file name in `Covers/` (App Group, else Application Support). `imageURL` holds the https remote URL if any.
`"none"` means the user removed the cover.

**Sync:** image bytes are **not** synced. Only `imageURL` (and the file name, which other devices ignore when the file is missing) travel in the jsonb. A user photo stays on the phone that took it; other devices show the tile (or re-fetch the page image).

**Share:** only an https `imageURL` is sent to `publish-recipe`; it is stored inside the `card` jsonb (and the existing `image_url` column), so no migration. The web page (`ate-legal/r/`) shows it as the hero and og:image.
*`publish-recipe` changes (https-only, optional top-level `image_url`) need a `supabase functions deploy publish-recipe`; the live function already stores `card.imageURL`.*

**Backfill:** existing recipes show the tile right away; when a row appears, an https `imageURL` is downloaded or the `sourceURL` page is checked for og:image (once per launch).
