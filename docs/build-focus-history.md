# Build-focus history requirement and checkout repair

The first hosted Journal run on source d663b966 failed before compilation: XcodeGen's preGen command called gen-build-notes.py, whose strict anchor ancestry check could not find f084a9fe in a depth-one checkout. Homebrew installed successfully; native build and all Journal tests were skipped. This is a source/checkout integration defect, not a simulator test failure. The failed run remains failed.

Repair: explicit `fetch-depth: 0` on all 14 shallow XcodeGen caller jobs across 12 workflow files. The caller inventory covers 24 XcodeGen jobs, including existing full-history Build IPA release/UI, Dogfood and retained branch workflows. Their existing full-history settings are unchanged. Compile, Journal, nightly, preproduction, CodeQL Swift and optional/manual callers now retain history too. Workflow names, job IDs, selectors, budgets, triggers, gate predicates and source refs do not change. More history transfer is a cost of preserving ancestry validation, not a performance claim.

The build-focus helper is unchanged: no unverifiable-ancestry fallback, guessed focus, implicit network fetch, or weakened blob check. Real depth-one fixtures reproduce rejection with no focus emitted, then prove unshallowing restores the same strict path. A caller-inventory test rejects a future shallow XcodeGen job.

Local builds also invoke the same preGen command through scripts/prepare-local-build.sh. Use a normal full-history checkout. If working from a shallow clone, fetch its history (`git fetch --unshallow`) before building. No runtime self-fetch is added to the notes generator. Missing or unverifiable source ancestry still stops the build rather than claiming a feature.

Evidence:
- https://github.com/melusi-k/ate-ios/actions/runs/42658425792
- https://github.com/melusi-k/ate-ios/commit/d663b966457a632b4a43460f14fe2a253d2adb99/checks/129303228594/logs/6

Offline tests do not establish a hosted repaired build, native About rendering, or device acceptance. Ordinary CI on the repair's final head is still required. No manual dispatch or retry is part of this repair.
