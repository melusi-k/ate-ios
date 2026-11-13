# Activation slice: extension conflict marker parity (OFF)

Builds on startup retirement1d2b7e83. SharedFileWriterGate now refuses old effects,
validation AND fresh epoch capture when the app's durable account conflict marker
is present. All checks run under the same flock as the app. Corrupt or symlink marker
entries are blocks, not fresh installation. Existing app-only mode makes no shared
protection claim and is unchanged.

This is required parity for the earlier c4a3c051 account-gate fence. Do not activate
that fence without this extension change. It still does not install the production
gate in extension entry points, solve immutable ancestor provisioning, or control
Watch's separate device filesystem. Those remain activation gates.

Two native tests add real AccountWriterGate→SharedFileWriterGate cross-instance
marker checks, including fresh/restarted extensions, corruption and dangling links.
Native compile/tests UNRUN.191 Python tests PASS, not native/device proof.
