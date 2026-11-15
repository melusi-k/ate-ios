# Add sheet identity: query hypothesis, not qualified fix

Exact base #537 804855f7e3789a02b92109cf1a8a033824c09f5e.
Native UNRUN. No waiver, publication, merge or closure.

Current CookIngredients scales/check/persist fails before Prompt, recipe
creation, Cook Mode or rice. The 229.642-second test failed before the Cook journey. The retained
2:50 recording shows the Link sheet with its heading visible in sampled
frames through 10:10 UTC. The recording does not cover the full test duration. The
failing query discovers ScrollViews containing the linkField TextField,
selects firstMatch, then asks for descendant StaticText containing Add a
recipe. The supplied debug text is this query chain, not an AX tree.
Target Main samples include matchingSnapshots and XCTest logging, but this
does not establish a product root cause or prove why the query stalls.

This packet adds one accessibility identifier to the sheet's existing
ScrollView and selects that ScrollView directly. It mechanically removes
the descendant-TextField-containing traversal and its firstMatch. The exact
heading predicate, active navigation existence/frame/hittable assertions,
waits, all following actions and every other test line remain unchanged.
No accessibility grouping, element type, layout or interaction is changed
in source; native AX exposure and pixels still require Reviewer evidence.

Cross-run comparison of retained logs: current #534 scales/check/persist
passes 70.138 seconds; earlier #537 terminal passes 81.922. Older #535
239.798-second failure passed this heading and Prompt, then failed later
in ingredients, so is not evidence for the same cause. Current #537's
normal-text and timer cases pass 91.563 and 59.756 seconds respectively.
These variable outcomes do not prove the proposed query change fixes it.
No broad reruns were performed. Journal hittable and Coverage32d landscape
remain separate open failures, unchanged by this packet.

Source contracts restore both entire original files after reversing only
the identifier addition/query substitution. Focus refresh is metadata only;
it must not be read as native qualification. The reviewer must confirm
native heading lookup, complete original cook journey and AX exposure.
Source PRs close only after reviewer confirms destination commit; branches kept.

The earlier rice-capture whole-file hash guard first reverses exactly this
query substitution (with an exact count check). Its original expected hash
and all original rice assertions remain unchanged. Initial full-suite run
exposed this source-guard conflict; the adapted guard and new exact-base
contract together retain both independent baselines.
