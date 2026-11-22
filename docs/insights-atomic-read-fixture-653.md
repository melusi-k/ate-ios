# Insights read-fixture rendezvous correction

Base: PR653 head7b9b12d4. Independent of CookPlan cancellation work.

The Health and prompt fixtures previously checked their read counts before registering an onRead callback. A producer could append its first continuation and invoke the absent callback between those operations. The later callback registration would then wait forever even though the requested read had already arrived. The helpers had no actor or lock isolation. That is a concrete fixture race, not proof of the native7b9 timeout's exact interleaving or an InsightsModel defect.

Both fixtures now use the same private generic rendezvous. Read storage, readiness checks and waiter registration use one NSLock. Arrival removes all satisfied waiters atomically, then notifies them after unlocking. Immediate notifications also run after unlocking. Read snapshots use the same lock. The helpers still suspend the actual Health/prompt continuations until the existing ownership tests explicitly resume them.

Two additional native tests replay both sides of the handshake without sleeps or timeout budgets. The lost-wakeup test observes no read, appends a read, then registers and requires one immediate notification. The second registers before arrival, checks separate thresholds and exactly-once notification, and reads a snapshot inside notification to require unlocking before callbacks. Both Health and prompt fixtures use this exact shared helper.

The four original ownership test bodies, their awaits, phase output and assertions remain byte-identical. No product source, workflow, selection, wait, timeout or cap changes. The new inverse restores the exact parent file before historical diagnostic guards; historical JSON fixtures are unchanged. Source guards pin the atomic critical section and reject stale-check, missing-lock, missing-drain and bypass mutants.

Validation: Python source/fixture suite only. Native Swift compilation and the two added tests require the next normal CI run. No native pass or7b9 timeout cure is claimed. Expected full-unit count increases by two if all other tests remain unchanged.
