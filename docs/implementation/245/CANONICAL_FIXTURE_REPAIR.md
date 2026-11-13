# Six fixture unsafePath failures

Exact base: f594a71bd0fc5ca596369f7821352c26e48f2b24.
Compile 43366475236, job 131691994956: 1104 units, six failures. All three FoodJournalArchiveConsumersTests fail at fixture line16 and all three FoodJournalDiskResourcesTests at fixture line13. Each is AccountWriterGate construction with unsafePath, before its substantive test body executes.

Comparison: all nine FoodJournalAppGraphTests PASS in the same run. Its fixture creates the temporary leaf, then resolves symlinks and standardizes the actual created URL. AccountWriterGateTests already uses this contract, introduced in 0c470f1011a611ec8c7ce964e880f531566a4ebd. The two failing fixtures instead resolve only the parent before appending/creating the leaf and omit standardizedFileURL. Their test files were introduced on November13; no earlier run of these six methods was found in the inspected history. This is a same-run source/behavior comparison, not an invented prior pass.

Repair only the two fixtures: create leaf, canonicalize that existing leaf with resolvingSymlinksInPath().standardizedFileURL, assert standardized identity and resolved-symlink identity, then pass it to the strict gate and all same-directory participants. Existing test bodies/assertions are unchanged. AccountWriterGate path checks, lstat/O_NOFOLLOW checks and every production source file remain unchanged. No fallback, retries, timeout change or test skips.

Native rerun is required for all six exact methods and the strict gate/AppGraph suites. These native tests are UNRUN here; Python source checks cannot prove Apple Foundation URL behavior. Activation stays OFF. Reviewer publishes/merges; source PR closure only after destination commit confirmed, branches kept.
