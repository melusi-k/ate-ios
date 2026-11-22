# Verify the cancelled-sheet round trip

8e05ce3f Nutrition UI14 is RED,14 tests/1failure. CookPlan no-reminder test49.009s fails its final cancel-button absence assertion. Cancel tap44.37s, underlying recipe.plan existence45.35s, reopen tap46.67s computes{-1,-1} at47.47s, cancel button exists47.79s. No post-cancel screenshot; retained screenshot is saved-plan before cancellation. Product persistence failure is unproved.

Older green retained native Compile44835322541/artifact14680580808:55.547s, cancel50.97s, underlying button existence52.64s, reopen53.88s, absence54.76s. Another older green46.279s computes valid reopen hitpoint{201,484}. Both older tests lack an explicit sheet-disappeared/new-sheet-mounted boundary. Their green does not validate that shortcut in the red.

Test-only correction adds strict saved-sheet disappearance before reopening, uncovered plan-button hittability, then reminder presence proving a newly mounted sheet before the unchanged final cancel-button absence assertion. Existing cancel action, save/reopen/persisted-reminder checks and final absence assertion remain. Same10s wait convention; no existing timeout/cap changes, retry, pass fallback or product change. It can expose an honest dismissal/mount failure rather than inspect the wrong sheet. Exact inverse restores whole parent source before historical Today-tab inverses, with historical fixture hashes unchanged.

Native validation pending, Python is source-contract evidence only. Prior named red stays red. No merge.
Sources: https://github.com/melusi-k/ate-ios/actions/runs/44970747415
https://github.com/melusi-k/ate-ios/actions/runs/44835322541
