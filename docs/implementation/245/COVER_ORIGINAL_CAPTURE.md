# Activation slice: cover original writer capture (OFF)

Builds on ledger28eada84. CoverStore now captures its boundary and validator before
starting async resolution/generation. ensure passes the same capture through page,
image, generator and AppStore publication; resolve's generation fallback never
recaptures a replacement authority. File/cache/attempt marker effects validate and
run through that original boundary. A refused marker effect stops BEFORE invoking
Image Playground instead of swallowing refusal and generating anyway.

Rebinding the shared singleton no longer changes the validator/boundary an old
operation will use. This still requires production bindings to actually invalidate
the old durable lease on auth/reset, and the returned filenames' external UI callers
to validate their own draft/session context. Loading/attempted state and task joining,
cache retirement, immutable cover folder and full singleton replacement remain
lifecycle work. This is not global quiescence or production activation.

Two native tests cover old captured authority after singleton rebind/await and
refused generate leaving no attempt marker. Native compile/tests UNRUN.191 Python
PASS, not generator/device proof. No visual layout changed.
