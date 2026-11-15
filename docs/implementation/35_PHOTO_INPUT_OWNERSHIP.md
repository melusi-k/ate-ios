# Recipe photo selection lifetime (#35 / #89)

Incremental on generation ownership a16f6fbc. Source finding: PhotosPicker loads
were unowned Tasks. A slow earlier choice could replace a newer source image;
a cover selection used whatever draft happened to be current on completion.

Each picker now has a latest-selection owner. Superseding input cancels the old
load AND revokes its token; cancellation-ignoring completion cannot publish.
Cover selection captures recipe identity before await, checks it after await,
and refuses writes during save. Discard, disappearance, save and generation start
invalidate both input loaders before external/persistent effects. A camera source
image supersedes a pending library selection; direct cover/remove choices revoke
pending cover-library loads. No layout, activation, test timeout or CI lane change.

Three new native fixtures cover reverse-order completion, revoked late input,
and a cover result arriving for a replacement draft. Exact named-pass registry
retains original25 + prior4 generation fixtures + these3 additions. Python source
wiring checks do NOT run Swift, PhotosPicker, camera or UIKit.

Native build/XCTest, system PhotosPicker/camera and physical-device persistence
remain NOT RUN. No new screenshot or visual-acceptance claim. Test on exact final
candidate; choose two images rapidly and confirm the latter wins, discard during
load and reopen without a revived draft, regenerate while a cover is loading and
confirm the replacement cannot inherit it, then save and relaunch. These are
pending checks, not proof or permission to run new paid/hosted cycles.

Remaining separate work: generated cover and cover-resolution tasks have their
own persistence behavior and are not changed here; the global on-device partial
preview sink still needs independent request scoping for concurrent spread parses.
No claim to close every photo/model/quality or lifecycle acceptance criterion.
