# Current-main merge and recovered-resource lease correction

Reviewer correction to cumulative f98dab0. Ordinary merge commit 9cf5e160 has parents
f98dab0cb009e0f96cee7dd03bc289af4b0c09f4 and current main
1015437a62fb7bf95b5222a29a7e9daae807bf94. No rebase. Main's full-unit verifier,
compile workflow and native guards are retained. Integration resolution starts
from main's complete tree and applies only the activation delta from a6a3146 to
f98dab0. AppStore initializer keeps main's CookPlan/auth constructor additions as
well as the new required consumer-capability injection. No root route switch.

FoodJournalDiskResources now retains the exact successful recovery gate and lease.
Both recipeContainer and makeResources enter that gate with the retained lease
before returning recovered data. A new epoch cannot bless old recovered objects:
repeat recover must match the original gate/lease/owner. New regression recovers
successfully, exercises both accessors, invalidates the epoch, then requires both
accessors and replacement-lease re-adoption to refuse.

All previous fourteen new tests remain; one new test added. Main's focused and
full-unit ledgers preserve all original entries in order and append these fifteen
methods only. The full-unit verifier implementation and compile workflow remain
byte-identical to main. No old test/source guard removal or timeout changes.

188 Python infrastructure tests PASS after merge and resource fix. Diff check PASS.
Fifteen native tests/build remain UNRUN. Production/root activation remains pending;
this packet is specifically the no-route-switch compile candidate Reviewer asked
for. No merge to remote, publication, deployment or personal-data mutation.

Rollback before production routing is the activation delta revert against current
main, not resetting the branch to the stale bundle. Preserve all main guards and
canonical bytes/recovery records. Retain source branches under the agreed gate.

Qualification correction: the 188/188 claim applied to the working tree before the
full-unit ledger addition, not final 0f44c725. Reviewer's final-head run correctly
found 187/188: the routing test's exact 34-name equality rejected added tests. The
correction retains its original 25+9 names and exact-order equality, adds a literal
15-name activation list and checks exact old34+new15 union. No wildcard, prefix-only
match, removed assertion or runtime/timeout change. Full Python suite is rerun on
this corrected candidate; old failed-head evidence remains recorded here.
