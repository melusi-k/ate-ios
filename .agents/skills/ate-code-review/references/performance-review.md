# Performance review checklist

Detailed gates behind the performance section of `../SKILL.md`. Adapted from [Dimillian/Skills swiftui-performance-audit](https://github.com/Dimillian/Skills) (MIT).

## Triage order

1. Broad invalidation
2. Unstable identity
3. Main-thread render work
4. Image cost
5. Layout/animation complexity

## Smells to flag

- Expensive formatters or calendars created in `body`.
- Sorting or filtering in `body` or inline in a `ForEach`.
- `id: \.self` identity on non-stable values.
- Top-level `if`/`else` that swaps whole view trees.
- Image decode or resize on the main thread.
- Many views reading one broad observable when each needs one field.

## What is not a fix

- `equatable()` is not a blanket fix: only when equality is cheaper than recomputing the subtree and inputs are value-semantic.
- `@State` is not a generic cache for expensive computation; precompute in the model or a helper with defined invalidation.

## Profiling evidence

For any performance claim that code review cannot settle, require profiling before naming a cause:

- Release build; name device vs simulator explicitly.
- SwiftUI Instruments template with Time Profiler; record the exact interaction.
- Compare before/after on the same build settings and device.

## Report templates

### Investigation intake

```text
Area:
Symptom:
Build (Release/Debug), device or simulator:
Repro interaction:
Suspected cause (hypothesis):
Evidence collected:
```

### Findings report

```text
Finding:
Likely cause:
Evidence:
Fix:
Validation (before/after metrics where available):
Confidence (confirmed / hypothesis):
```

A conclusion stays a hypothesis until evidence confirms it; say so explicitly.
