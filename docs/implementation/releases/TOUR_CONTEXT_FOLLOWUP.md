# Release Notes follow-up: selected release context in the tour

Base:97ed1c692ad816ad8121deef431bc5a098519a43 (#529).
Each tour page now starts with its selected release title and version (Beta when
applicable). Context scrolls with the existing page, not another fixed header.
Page-specific identifiers avoid duplicate global identifiers across TabView pages.
Original bundled catalog, placeholder disclosure and all existing tour controls
and navigation are unchanged. No new network/storage/activation or gate copy.

Existing normal-text Release Notes journey additionally checks first/second page
context, expected version and consistency, retaining all previous assertions and
screenshots. One source-contract test guards data-derived context. Runtime pixels,
normal-text fit, typecheck/warnings and native XCTest remain UNVERIFIED. Reviewer
must inspect existing first/last tour captures at exact final head before visual
acceptance. Do not infer native fit from source. No dispatch or production changes.

Build-focus guard intentionally unchanged. ProductUpdatesViews evidence becomes
stale with this runtime change; publish reviewed runtime first, then refresh focus
against the actual hosted ancestor/blob and independently review metadata before
fresh native CI. Do not remove evidence or weaken guard to bypass the stale pin.
