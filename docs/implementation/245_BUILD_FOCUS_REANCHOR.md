# Build-focus reanchor for the retained graph

Base: 870ff3199d85d7f9a4d75c868545af1f32810cb7, tree c8e534f6.

The inherited build focus pins JournalViews.swift blob 61c2d7df from source
7c3f7d02. Bound-media work changed it to 9345ba42, so build-focus.py correctly
refuses before project generation. AteApp.swift still matches its old blob.
This is a stale reviewed evidence record, not a build/test result.

Reanchor the record to the exact retained-graph ancestor and actual app Swift
blobs: unchanged root, bound Journal view, admission/retained graph, local owner,
consumer lifecycle and archive import/export. Copy explicitly states dormant
preparation, activation OFF, no production backend/anonymous-login changes,
native qualification pending, and cooking is not eaten food.

No guard, workflow, runtime, test selection or timeout change. Future changes to
any pinned source still fail closed and require another reviewed focus update.
