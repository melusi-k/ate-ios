# Draft test registration handshake

On b40635b5 full-unit job137005649200, testDisappearKeepsRetryInputButLateResultCannotReplaceIt failed its strict2s returned expectation (2.867s total). The source and DraftGenerationAttempt product owner are identical to current mainffa7fdcf. Earlier retained native passes were0.007–0.015s, including0.011s on ed82. This is not evidence of an established main flake, nor proof of a product failure caused by653.

The fixture previously signalled started before awaiting parse and registering its continuation. complete optional-chains resume and clears the slot. Completion before registration can therefore lose the signal. This is a source-supported race hypothesis, not a measured ordering in the failing run.

Only the failing test now fulfils started from a callback immediately after the backend stores its continuation. The helper's default nil callback leaves all other call sites intact. No actor annotation, timer, retry, timeout, production code, late-result assertion, invalidation, completion, or persistence check changes. A pinned inverse recovers the exact whole original source and independently permits only these two hunks. Native validation is pending; a pass will not prove the earlier ordering.

Source: https://github.com/melusi-k/ate-ios/actions/runs/44956473155
Journal green on this head remains separate evidence. Prior full-unit reds remain red.
