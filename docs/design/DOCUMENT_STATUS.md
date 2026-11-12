# Design and architecture document status

Status: Current

Decision owner: Melusi Khumalo. Approved direction: 12 November 2026, [Discussion #487](https://github.com/melusi-k/ate-ios/discussions/487). This convention governs document labels only, not approval of the existing design-review process, architecture proposals or implementation scope.

## Three statuses

- **Draft:** proposed, provisional, in review or not approved for reliance as current design policy. Keep the review stage, source baseline and unresolved decisions visible.
- **Current:** approved for the stated scope. Record the owner decision and exact reviewed revision. A current navigation index does not approve its linked drafts. Current design intent is not proof that the app implements it or that tests passed.
- **Archived:** retained for history, not active guidance. Record the date and replacement link or why no replacement exists. Do not erase historical findings or failed evidence.

Put `Status: Draft`, `Status: Current` or `Status: Archived` near the title in design and architecture records. For new records start Draft. Status and evidence are separate: retain source SHA/date, implementation state (Implemented / Partially implemented / Proposed / Needs verification), verification limits and owner/review provenance.

Promotion needs a recorded owner decision for the exact document revision and its scope. Approval of one decision is not approval of unrelated draft content. When replacing a Current record, archive it with a forward link and link the replacement back. Do not relabel historical product contracts in bulk; correct drift with dated addenda in their owning records.

The initial adoption labels the token baseline, design-review proposal, architecture proposal and template Draft. It does not re-certify their historical source claims. The architecture index is Current for navigation only. No app, token, Figma, CI or release gate changes follow from these headers.
