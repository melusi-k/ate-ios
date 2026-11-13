# Main feature focus in build notes

Every new build's notes open with its reviewed main feature focus, before source changes, What to test and How to test. This names the purpose of the build, not a test pass or release approval.

Update `docs/build-focus.json` when selecting the next build's focus. Use a concise title and summary, a full ancestor source commit, and exact app Swift path/blob pairs that support the claim. Review what the target build actually contains. Do not infer shipped functionality from a PR title, tests alone, dormant preparation, or unmerged work.

The renderer reads this record from the target source commit, never from a newer checkout. It checks source ancestry and unchanged evidence blobs. Only the listed evidence files are guarded. The current record unions AteApp, JournalViews, CookModeView and RecipeDetailView with JournalSuggestionService for reflection commit results and confirmed deletion. Other runtime paths are not guarded unless explicitly added as evidence. This is not an all-runtime stale-focus detector. Those checks prevent several stale-source mistakes but cannot establish that a feature is active, correct, or accepted on a device. Source review still owns that judgment. Runtime evidence changes require a fresh review and record update. Historical source commits without a record say that no focus was recorded.

The release notes and generated in-app About notes use the same renderer. No change to versioning, channels, publishing, qualification or promotion rules is made.

For a generation-evaluation build after #254 is included, review and update the record to that build's generation focus. Until then, do not name #254 as the focus of a main build. Device/model evaluation remains pending regardless of source inclusion.

Native rendering of the updated About notes has not been verified. Offline tests check generated text only.
