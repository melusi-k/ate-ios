# Journal delete-alert descendant query correction

Base: f6949b44, the first UI-only Journal qualification head. This correction is test-only.

## Evidence and comparison

Journal run 44999800313 executes 27 tests with one failure and no skips. All four CanonicalUpgrade cases pass, including the formerly failing first launch; the required reflection-edit retry UI case also passes. The sole red is manual reflection CRUD, at its first delete-alert Cancel identity check, before the tap.

The retained pre-count image shows one visible Cancel and one Delete. The AX tree represents each as an equal-frame parent/child Button pair. At 08:08:29Z the hierarchy is still returned. Descendant query counts under indexed aliases then slow and retry until the unchanged 240-second case allowance expires. The 08:10:58-08:11:03Z spindump locates the runner in uniqueDeleteAlertAction at line63, XCUIElementQuery.count and a synchronous remote query wait. The app main thread is idle in its run loop in that sample. The sample is later than the pre-count image, so it is not proof of uninterrupted app responsiveness throughout the interval.

The same manual case passed on c204 in 113.643s. Retained 0ce8 and 8e05 Journal roots are both 29/0/0. Earlier 8a05 and e69 manual CRUD reds occur after confirmed Delete, while checking an absent detail element, not at Cancel action resolution. These are distinct boundaries. c204 CookPlan also differs: Cancel is tapped, queries keep returning a still-mounted busy sheet with Save and Done disabled. There is no common cancellation-handler cause established.

## Narrow change

Keep the existing alert count, named-action presence, same-label identity coverage, every-alias label, all-descendant identity, one-terminal-action, visible frame, containment, equal-frame aliases, enabled state and live hittability assertions. Keep the same live terminal XCUIElement for the eventual tap.

Replace only the two lines constructing a compound descendant query and its identifier subquery. Capture one public immutable snapshot per candidate and walk its captured child tree locally. The walk excludes the root, includes all matching descendant buttons, and never filters or merges by identifier, label, frame or enabled state. Invalid siblings and foreign decisions still reach the unchanged assertions and fail.

The exact generic walk is shared with AteTests through one test-only source-list addition. Six native adversarial cases cover a terminal leaf, nested aliases, equal-frame sibling decisions, a foreign identifier, nonbutton containers and invalid metadata. All six become required native passes in the existing full-unit manifest. No app target source, native journey body, timeout, retry, skip, workflow or gate changes. Journal stays 27 cases; full units are expected 1354 (1348 + 6), subject to the next normal native result.

Historical JSON pins are unchanged. Exact inverse guards compose the new allowed delta before the existing source reconstructions. Source/Python checks do not qualify the new native head; one ordinary descendant qualification cycle is still required. No merge or waiver follows from this packet.

## API sources

- https://developer.apple.com/documentation/xcuiautomation/xcuielementsnapshot
- https://developer.apple.com/documentation/xcuiautomation/xcuielementsnapshotproviding/snapshot()

Apple describes a snapshot as attributes and descendant hierarchy, exposed through child snapshots. The correction does not add a package or depend on a third-party snapshot library.
