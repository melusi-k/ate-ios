# Confirmed-delete negative lookup candidate

Current e69df986 Journal native job136987755523 is RED. The post-confirmation screenshot shows Journal root and the deletion toast, without detail. The first negative detail-existence lookup occupies9.304s of the unchanged10s expectation, followed by two short internal retries and a timeout. No sample covers that lookup; its return value and app-versus-runner cause are unknown. The earlier current-query correction was insufficient.

This candidate changes only that final absence query to require zero descendants with the exact journal.detail.text identifier. It does not resolve a missing firstMatch. It preserves the10s waiter and .completed assertion, delete-error check, positive Journal-root check, and created-entry history absence check. It does not change the product or confirm/cancel actions. Count lookup speed is unproved. A native pass is not proof of root cause.

The pinned exact inverse restores every original UI-test byte before existing current-query and historical inverses. Historical fixture hashes remain unchanged. If this candidate repeats the failure, capture a sample during the negative lookup; do not try another query variant or change the timeout.

Source: https://github.com/melusi-k/ate-ios/actions/runs/44950677702/job/136987755523
