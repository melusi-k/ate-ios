# Food Journal graph-transition prerequisite

Source-only child of the owned-consumer packet. Activation remains OFF. This is
not complete production integration and must not be presented as an ON build.

## Ownership

`FoodJournalGraphTransitions` belongs to the root host, outside the old graph's
consumer registry. The host must remove editors and await their actual completion.
The lifecycle then revokes the original epoch, cancels consumers and drains all
results. Its single replacement-epoch handoff rechecks the retained session,
receipt and reset-control proof before session persistence. Import validates first,
uses the retained import transaction, and rebuilds only after commit. Reset invokes
the durable reset protocol after quiescence; an unverified result throws. Neither
path returns the old graph to ordinary UI. Retirement failure still attempts to
revoke/drain the old graph and never rebuilds it.

AppStore exposes explicit async callbacks for session, import, reset, delete and
sign-out-with-data removal. These callbacks are nil on the dormant path. Ordinary
sync is registered with the captured graph when supplied; concurrent ordinary sync
is refused while one is running. Token refresh dispatches a root transition outside
its own consumer before returning, avoiding self-drain. Root must not put the
transition itself inside this task registry.

The new sync adapter compares full session identity and exact durable owner and
generation before publishing snapshot rows or pushing. A pull capture authorizes
one push only. Failed or mismatched pulls clear that authority. It never adopts an
advanced remote generation, silently switches owner, or falls back to direct table
POST. A remote reset remains a blocked reconciliation, not permission to stamp old
local bytes with a fresh generation.

## Remaining final-layer requirements

- Real lazy startup/reset resume before any ordinary store or service is opened.
- Actual editor/task retirement and all service bindings, not no-op callbacks.
- Verified account-wide reset inventory and durable cleanup/status continuation.
- Root replacement/re-admission after import/reset/auth, including callback intent
  restoration (password recovery must open new-password UI in the replacement).
- Inject this generation transport in place of legacy sync.
- Final flag ON and native UI evidence only after those bindings exist.
- Production contract deployment is separately authorized work. Source contract
  dependency is the PT409 fix at 841c14ee1975949dc1542bf24b0f4795ef089354;
  the v2 stack cherry-picks that source fix as a separate dependency commit, including
  its SQL and tests. It deploys nothing.
  The reviewer must reconcile that dependency before qualifying activation.

## Verification

Python source tests, Swift grammar parse of all eight changed/new Swift files, and
`git diff --check` pass locally. Five focused native test methods added to the
full-unit required manifest (81 to 88, including two PT409 methods). Native compile/tests and Settings pixels
are UNRUN here and required from the reviewer. Grammar parsing is not typechecking.

## Reviewer v2 correction

Any import failure after editor retirement, including unarchived/corrupt recipe
links or migration failure before importer quiescence, now attempts graph quiescence
and drains registered tasks, then rethrows the original error. No rebuild occurs.
A focused corrupt-links native regression proves editor/cancel/drain order, revoked
writer lease, inaccessible old graph, no rebuild, unchanged link bytes and original
error identity. Structural file validation remains before retirement.

PT409 cherry-pick resolved modify/delete conflicts by retaining the exact dependency
versions of its migration, SQL tests, Python contract and review document, absent
from the factory base. No bespoke SQL changes and no deployment were performed.

The exact dependency rollback guard source was also restored because the migration
contract test requires it; it refuses rollback after a reset. It was not executed.
