# #157 Cook state and bottom chrome candidate

Incremental on prior Cook Finish candidate25f4451. Keeps its Finish reserve,
portrait/landscape tests, actual retained Resume accessory and completion check.
No publishing, merge, Journal activation or native/device pass.

## Grounding

Original4912b086/run39710638199 Coverage artifact records the genuine pushed
RecipeDetail Cook button vs timer mismatch797>760.333 at line547. This is not
CookMode Finish, so the older Finish packet alone does not close it. The later
740f81ad/run42610132681 account/presentation focused artifacts contain none of
the six named #157 methods; a green aggregate does not supply per-case proof.

- https://github.com/melusi-k/ate-ios/actions/runs/39710638199/artifacts/12397946788
- https://github.com/melusi-k/ate-ios/actions/runs/42610132681/artifacts/13672083398
- https://github.com/melusi-k/ate-ios/actions/runs/42610132681/artifacts/13671793321

## Candidate

CookMode no longer owns a private State step. Its current step is a clamped read
of the matching shared cookSession on every render; local buttons/voice writes
use that owner. On appear only creates a missing session, never overwrites a
saved shared step with the step of an older parallel timer. The onChange hook is
feedback only, not a second write path. Finish write guards remain; stale views
cannot replace a session for a different recipe via their step setter.

RecipeDetail reserves the measured obscured bottom band for the outer stack's
Resume/timer chrome, using the existing bottomChromeMinY environment, not a fixed
device-specific bar height. The outer Resume+timer group is an explicit VStack,
so both siblings form one measured inset instead of relying on Group layout.
The previously delivered Cook Finish measurement is retained.

Adds a synthetic UI external-step control (UITesting+explicit argument only) that
writes AppStore.cookSession directly while CookMode is open. The journey requires
Next to become Finish without reopening; checks local Back and repeated external
change, then reopen retention. This is observation wiring proof, not a physical
widget/Live Activity execution claim. Existing account-cooking step also selects
this method and the unchanged original detail overlap method and requires each
named pass, plus existing portrait/landscape Finish methods. No removed assertion,
extra runner, timeout increase or broad dispatch.

## Remaining qualification

Python185PASS/diffcheckPASS only. Swift/native and actual updated pixels NOT RUN.
Both geometry reserves need real iPhone18Pro portrait/landscape screenshots with
Resume AND timer visible; verify no double reserve/large gap and that Ask Ate is
reachable. No fixed-pixel readiness claim. Exact-head full CoverageUITests still
required for #157, not only these selected methods. Backend/Health/Journal/back
historical cases remain separate until individually verified.
