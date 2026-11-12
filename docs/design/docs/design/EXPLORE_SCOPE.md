# Explore: local discovery for the cook loop

Status: Draft

Owner requested Explore and live shopping sync on 12 November 2026, Explore first. Candidate baseline: main `628f444`. Tracking: #73, then #72/#34. Source inclusion is not device acceptance.

## This slice

Library has a separate Explore button, not restored Journal/Insights menu shortcuts. Its large sheet reads the saved recipe store and the active runtime's cooking history. Sections are 30 minutes or less (positive known time, fastest first), favourites (newest first), and Cook again (actual completed-cook day, then newest). Stable ID breaks ties. A recipe can belong to more than one section; duplicate IDs and deleted history references do not become duplicate cards. Old lastCookedAt alone does not prove a completed cook.

Selection dismisses Explore before opening the existing recipe preview/detail sheet. Planning, adding ingredients and Cook Mode remain existing detail actions; this slice does not create another cooking path. Done preserves Library query, filters, order and navigation. Empty library offers Add recipe after dismissal; empty sections explain how to populate them.

No server catalogue, trending/popularity claims, model ranking, network request or paid dependency. Saved discovery works offline. Thumbnail loading keeps the existing RecipeRowView behaviour; no offline-image availability is promised. "Explore" is bounded saved-library discovery, not a claim to discover an online catalogue. Broader discovery needs a separate product decision and source/licensing review.

## Verification needed

Four native unit cases cover collection membership, exact30-minute boundary, completion-vs-open identity, stale references, deterministic ties and nonmutation. Five UI cases capture portrait/dismissal, landscape, empty/Add handoff, recipe preview/detail selection and collection/query preservation. Compile presentation-creation explicitly selects ExploreUITests and retains xcresult plus exported attachments; five named passes are required, not a zero-test green. Existing selectors and timeouts are unchanged. Native tests and rendered pixels have not run in this environment. Existing Library/search/filter/history acceptance is not automatically closed. Before acceptance, inspect portrait/landscape normal text and exercise recipe selection, add-from-empty, filter/query preservation and deleted selection on the exact candidate.

## Shopping sync next, not silently declared unbuilt

Current AppStore and SupabaseSync already pull/push shopping rows with local metadata and tombstones, account-switch guards, foreground sync and mutation debounce. Audit is needed before replacing this with a second engine. Existing equal-millisecond conflicts can diverge (strict-newer comparison keeps each local value); blind PostgREST upsert is not server-side LWW. Foreground remote receive/retry and concurrent same-account sync need explicit review. Real two-device evidence, authenticated server conflict guarantees and activation remain #34/#72 work, not proven by the Explore slice. No production schema/policy rollout is included here.
