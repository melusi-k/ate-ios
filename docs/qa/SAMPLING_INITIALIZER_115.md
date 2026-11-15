# #115 Foundation Models initializer slice

Base main: `4aa5e5ed62c84cba4bb9a9008ae35810956d91ae`.

Changes exactly one production argument label: `GenerationOptions(sampling: .greedy)` to `GenerationOptions(samplingMode: .greedy)`. The retained native compiler warning explicitly names the replacement initializer. Greedy sampling and the absence of explicit temperature/maximum-response-token options remain unchanged. Session reuse, input, generation, OCR, deadlines, retries and acceptance are untouched.

This is only the initializer clause of #115. Locale percentage formatting, individually reviewed recommended project settings, focused native generation/localization tests and exact-head warning validation remain OPEN. No project/SDK/deployment/signing change is made.

The supplied warning excerpt is from retained hosted build output; it is historical evidence for the compiler-directed replacement, not a new clean build or proof that every warning still exists. Source contracts reconstruct the exact original backend and freeze project.yml and existing native prompt/OCR/QA fixtures.

Native compilation and generation behavior validation are UNRUN. Reviewer must build the exact candidate with the current supported Xcode, confirm the initializer deprecation is absent without new warnings/errors, and run focused prompt/generation tests plus a device comparison. #115 cannot close from this slice alone.

Source PRs close only after the reviewer confirms the destination commit; branches kept.
