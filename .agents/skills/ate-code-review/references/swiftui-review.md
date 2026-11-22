# SwiftUI review checklist

Detailed gates behind the SwiftUI and accessibility sections of `../SKILL.md`. Adapted from [twostraws/SwiftUI-Agent-Skill](https://github.com/twostraws/SwiftUI-Agent-Skill) (MIT); checked against Ate's iOS 18.0 deployment target and Swift 5.9 language mode.

## View structure

- Long `body` implementations or computed properties returning `some View` become extracted `View` structs.
- View initializers stay trivial; defer real work to `task()`.
- `@State` is `private`, initialized in exactly one place.
- `ForEach`/`List` identity comes from the element's stable id. Flag `id: \.self` on mutable collections and any index/offset-based identity: stale renders and lost state follow from it.
- Actions and business logic live in methods or model types, not inline in `body`, `task()`, or `onAppear()`.

## Modern API gates (all available on iOS 18.0)

- `foregroundStyle()` over `foregroundColor()` (deprecated styling).
- `clipShape(.rect(cornerRadius:))` over the deprecated `cornerRadius()`.
- `NavigationStack` + `navigationDestination(for:)` over `NavigationView`.
- `.scrollIndicators(.hidden)` over `showsIndicators: false`.
- `onChange(of:)`: two-parameter or zero-parameter form only; the one-parameter closure variant is deprecated.
- `Text` built with interpolation, never `Text(a + b)`; concatenation loses localization and formatting.
- `Tab` API over `tabItem()` when touching `TabView` chrome (Tab API requires iOS 18; the deployment target allows it).

## Accessibility

- Dynamic Type everywhere; flag fixed font sizes.
- `Button` over `onTapGesture()` unless tap location/count is genuinely required.
- Icon-looking controls keep a text `Label` with `.labelStyle(.iconOnly)` so VoiceOver reads a label.
- Interactive targets at least 44x44 points.
- Assert on stable accessibility identifiers in UI tests (see `ate-testing`).
