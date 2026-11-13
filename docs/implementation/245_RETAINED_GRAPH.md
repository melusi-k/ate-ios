# Dormant admitted graph with real archive proofs

Parent: 8a5ed300f8073e69dce4c2a52dd1d42f15eb3c58.
Activation OFF; no AppStore/RootView callback or auth transition installed.

Successful ProductionAdmission can build exactly one retained graph, from its
original successful proof, owner resources, full session and gate lease. The
graph's initializer is fileprivate beside admission, preventing ordinary
consumers from assembling arbitrary storage and callback combinations.

Lifecycle validation is bound into every owner write. Export uses that owner's
actual recipe container and retains ordinary admission/lifecycle validation.
Import receives the current receipt owner identity and a concrete post-drain
proof: unchanged captured session, receipt and no pending reset. It executes
under the lifecycle's replacement epoch gate; it must not check the revoked
ordinary writer lease. This closes the previously caller-injected identity gap.
Reset inventory comes from the same retained owner, not reconstructed globals.
No cycle references the graph: services retain admission/lifecycle, while
admission does not retain its returned graph.

Three required native methods cover shared domains, drain-before-import,
old-graph export refusal and duplicate graph refusal; receipt mutation during
drain with zero recovery transaction; same-owner token change refusing both
archive routes before effects. Required union 75 to 78.

Python discovery 202 PASS; two Swift grammar parses and diff check PASS.
Native build/tests/pixels UNRUN. Root still must register all actual consumers,
close editors, await drains on auth transitions, install archive callbacks and
rebuild/re-admit after import. Generation-fenced sync and activation remain off.
