# Cook countdown ownership and static recipe AX cost candidate

Base: 99731debf4ebb4cf67111fae954859a467824b12 (#522).

## Measured before, no measured after yet

Compile 43366607387, account job 131694072883 and presentation job 131694073005. Full individual UI logs inspected, not only grep/tail excerpts.

Sheet test32c: generation/save/root return32.53s; compact preview41.19s; full detent50.89s. The first STEPS scroll starts57.13s and finishes idle70.80s. Repeated heading hittability lookups cost83.68/97.16/107.14s despite no further swipe. Collapse requested122.19s and completes135.42s; preview lookup145.62s; portrait closes158.80s. Landscape preview168.18s, expanded173.21s, close178.70s, timeout179.71s, sidebar round-trip and teardown188.96s. The final close is not a deadlock; most variable cost is portrait AX/hittability around scrolled detail.

Prior Compile43359138003 presentation job131668348474 checked out3a0b1afa61a65bab8f5527fa2e5a9f4fdfca725c and the same test PASSED125.827s. Core sheet, test, Cook, TimerCenter, app, components, cover and nutrition view sources are identical between those heads. RecipeDetail changes are untapped Ask/Repair actions and text; UI tests use unchanged MockBackend, not changed OnDeviceBackend. No causal claim that #522 introduced this slowdown. Main classified it as an existing performance defect. Prior job log contains a named pass, not individual step timing.

Cook test06 starts timer63.37s then blocks waiting for idle63.99-115.28s. Pauses/resets123-125s; finishes162.87s, tears down172.21s but reports timeout/passed206.052s. Next completion test fails at app.launch line63 terminating that preceding PID before a Cook action. Existing runner restarts; completion passes94.022s and explicit exit passes38.075s. That restart is not qualification of the initial failure and is not added by this patch. Launch-termination root cause remains unproved.

## Source changes

- CookModeView no longer reads TimerCenter.now anywhere. It observes timer collection/state for controls, while CookTimerCountdown owns the current step's clock read and spoken/visible value. A running sibling timer's dynamic text and spoken action belong to CookOtherTimerButton. The unchanged500ms tick/expiry engine therefore invalidates these small leaf bodies, not full step text/controls/sheets/navigation.
- TimerBar/TimerRow remain their own existing narrow clock consumers. No timer duration, expiry, start/pause/reset, persistence, generation, notification or background behavior changed.
- Each static recipe ingredient amount+name and step number+instruction becomes one combined spoken row. All text remains, no control is hidden, and STEPS heading remains separately mounted/addressable. No lazy materialization, sheet reconstruction or state reset. This reduces static semantic AX targets and improves reading order; it is a bounded cost candidate, not measured proof that it removes the snapshot delay.
- Original UI tests, loops, waits, assertions, execution budgets and CI are unchanged. No retries/polling/timeout increases.

## Qualification

194 Python checks PASS, including three new source ownership/AX grouping checks. Two new native observation tests check structural reads do not invalidate on clock-only updates while clock reads still do. They are UNRUN. One added native UI test requires exactly one ingredient and step combined node with quantity/name/number/instruction retained plus separate STEPS heading. UNRUN. Swift compile, countdown redraw pixels, VoiceOver reading order, retained servings, AX counts and before/after performance are UNRUN here.

Reviewer must run exact head's new tests and original unchanged test06, completion/exit journeys and test32c under existing budgets. Retain full timing logs and pixels. Compare the51s timer-idle wait and57-145s portrait lookup region to measured before; a merely green run does not establish a speedup. If label grouping loses spoken data or doesn't help AX cost, stop/revise rather than weaken tests. No claim that this fixes the launch-termination failure without measured evidence.

Reviewer publishes/merges; branch-only. Source PR closure only after destination commit confirmed; branches kept. Full Food Journal activation remains OFF.
