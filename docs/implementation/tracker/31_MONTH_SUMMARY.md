# #31 first slice: recorded cooking month summary

Branch-only, base6f9fe56fc3fc3a8a544d79450006592a6316b375. No publish,
merge, PR, workflow dispatch or issue closure. Local history read only.

Calendar displays recorded cooking days and distinct recipe IDs for its displayed
month. Repeated recipe on different days counts each day but only one distinct
recipe; deleted-library recipe IDs still count because the cook record remains.
Zero history is explicit. This is not a count of meals eaten, servings or sessions.
No new completion/migration/persistence/Health/network/sync behavior.

Pure CookingMonthSummary reads existing local day keys and validates dates by
calendar roundtrip before counting. Month/year/leap boundaries and empty/invalid
records do not inflate summary. Stored day components never become UTC instants
for month allocation, so timezone changes do not move existing records across
months. Calendar rendering/arrow/day-sheet logic otherwise unchanged.

Three required native unit methods added, all previous required entries retained:
unique days/recipes/deleted IDs, month-year-leap/invalid/empty boundaries, stored
local-day month across four timezone calendars and explicit zero copy. New normal
text tracker UI test captures current/previous month summary and confirms future
restriction remains. Existing native assertions/waits/timeouts untouched.

207 Python PASS; diff-check and Swift grammar checks PASS. Native build/warnings,
XCTest and actual rendered pixels UNVERIFIED because no Xcode/simulator is available.
Reviewer must inspect exact-head normal-text screen captures, including caption
wrapping and calendar visibility, before accepting UI. No physical-device claims.
Full #31 gate and #60 device work remain open, not closed by this bounded slice.
https://github.com/melusi-k/ate-ios/issues/31
