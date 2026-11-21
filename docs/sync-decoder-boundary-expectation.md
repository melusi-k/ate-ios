# Near-limit decoder assertion: decimal versus binary value

20 November 2026, branch-only correction on PR632 c59674c6. Native final-head execution UNRUN. Production code is unchanged.

## Cause

Full-unit native log full-unit-tests-947dba0b.log lines3535–3541 reports one failure at SyncPayloadSafetyTests.swift:75: decoded9223372036854775000 differs from expected9223372036854774784. The newly introduced test interpolates Double(Int.max).nextDown into JSON, but compares the result against Int of that binary Double.

Those are not the same exact input value. The binary Double represents9223372036854774784. Its shortest round-trip decimal exponent spelling is9.223372036854775e+18, which denotes the exact integer9223372036854775000. RecipeCard.legacyInteger deliberately attempts decode(Int.self) first, then bounded Double truncation only if integer decoding fails. The native result shows the integer path preserving the exact in-range decimal integer. Rounding it through Double to satisfy this assertion would lose precision and change the intended product contract.

The expectation defect was added in our new boundary test, not established as a product decoding failure. The original overflow crash and malformed payload rejection are separate: this packet does not alter their fix or assertions. Python decimal/binary arithmetic corroborates the216 difference, but is not Swift/native proof.

## Correction, without weakening

- Serialize Int(Double(Int.max).nextDown) as an exact integer JSON token, assert that integer is exactly9223372036854774784, then require both servings and timeMinutes to decode to it.
- Explicitly decode the original positive exponent spelling and its negative counterpart. Require both numeric fields to equal their exact decimal integer values, positive/negative9223372036854775000. This retains coverage of the actual native-failing input rather than dropping it.
- Preserve every existing out-of-range rejection, exact Int.max/Int.min check, fractional truncation and missing-field assertion byte-for-byte outside this replacement. An inverse-source guard proves that scope.

No approximate comparison, broad no-throw substitute, removed case, default substitution, tolerance or production conversion change. No workflows, timeout changes, retries, remote publication, dispatch/rerun, merge or QA-result writes.

Reviewer next: retain the original failure log, execute the exact decoder method and existing malformed/overflow/draft tests on the final head, then full native units under existing budgets. Require exact integer expectations and no process trap. This source correction does not itself qualify Swift or establish a final-head native pass.
