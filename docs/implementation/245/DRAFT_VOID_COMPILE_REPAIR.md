# DraftStore generic Void effect compile repair

Exact hosted union base: f397699655b7bdbfbc684bf7b9feff46c4b7879e.
Compile 43379504278 job 131733766142 reports missing-return errors in DraftStore effect closures at lines 28, 40 and 44. These multi-statement side-effect closures feed a generic withEffect<T> wrapped in try? and compared to nil. Generic result inference selected an unintended optional metatype rather than the intended Void result.

Each of the four DraftStore effect closures now explicitly declares () throws -> Void, including the single-statement end closure for one consistent contract. No storage logic, Bool result interpretation, boundary, test assertion, runtime gate, disabled no-op behavior or encode-before-retiring-pending ordering changes. A successful Void effect still returns a present Void? through try?; an exception still returns nil and false.

Added a native test requiring all four admitted calls to return true, run exactly one boundary effect per call, and preserve/clear the expected persisted fields. Existing rejected/retired-boundary tests remain unchanged. The new test, native compile and native suite are UNRUN here because no Swift/Xcode runtime is available. Reviewer must rerun the exact new head's account and presentation compilation lanes and DraftStore tests. Activation remains OFF; this is not full graph/reset acceptance.

Reviewer publishes/merges. Source PRs close only after destination commit confirmed; branches kept.
