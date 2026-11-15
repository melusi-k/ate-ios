# Retained reset inventory (#245, safety correction)

The dormant unified account-action wipe previously reconstructed paths using
JournalLocalReset(runtime:). That constructor uses global media, store and backup
locations, so it could wipe a different domain than the retained runtime.

The action now requires a retained explicit inventory before entering any effect
or changing personal data. Missing inventory, foreign Journal/defaults or media
mismatch fails with reset-inventory preflight evidence. The action executes the
retained inventory, not a newly inferred global inventory. The local owner from
the preceding packet supplies the correct inventory for later graph assembly.
There is still no production caller or activation in this slice.

Existing positive wipe tests now bind explicit isolated inventory and use a
custom media domain. Every existing assertion is retained. Two new required
native fixtures check missing and foreign inventories preserve meals and never
enter the personal effect. Python guards pin the preflight ordering and no-global
reconstruction. Native build/test execution remains pending exact-head CI.

This does not implement quiescence, full graph assembly, account-wide reset or
archive import/export. Those remain required before activation. Personal
preservation bytes remain part of the explicit owner inventory. #245 stays open.
