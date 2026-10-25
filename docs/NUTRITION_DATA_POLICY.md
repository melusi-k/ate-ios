# Nutrition data policy

## Recommended path

Use a small, bundled USDA FoodData Central (FDC) subset for generic foods that have an exact preparation-state match. Keep it available offline and do not make the diary depend on a live API. FDC states its data are public domain under CC0 1.0, permits reuse without permission, and requests attribution. Its public API requires a data.gov key, so that key must never ship in the app. Sources: [FDC licensing and API guide](https://fdc.nal.usda.gov/api-guide/) and [FDC dataset downloads](https://fdc.nal.usda.gov/download-datasets/).

This is the best near-term customer path because it can work offline, needs no account, avoids a runtime service/key dependency, and makes each displayed value traceable. It does not make FDC a universal food matcher: Ate must not substitute a vaguely similar U.S. food for a South African ingredient or prepared dish.

## Record inclusion rules

Every bundled record must retain:

- FDC ID, data type and release/version;
- original FDC description and a plain-language display name;
- raw/cooked/preparation state and whether the record is a sound match for the display name;
- reference quantity and nutrient units;
- only nutrients actually present in the source; missing nutrients remain unavailable;
- source link and the date the record was checked.

Curate from FDC Foundation Foods, SR Legacy, or FNDDS when the record description and state match. Keep branded-label records out of the starter set unless they add clear customer value and can be kept current. Review each row against the original record before shipping; do not populate the catalogue by fuzzy name matching alone.

## Diary behavior when no exact match exists

Show “Not in catalogue” and let the person log the food by name. Nutrient fields remain unavailable unless the person enters values and identifies their own source, such as a package label. Mark those values as user-provided; Ate has not independently verified them. Do not use an approximate food record to fill missing values. A later exact catalogue match may be selected for future entries, while existing diary entries keep their nutrient snapshots.

Prioritize local staples such as pap, samp, beans and familiar cooked dishes for a future South African data pack. Add SAFOODS records only after commercial-use rights are explicitly confirmed in writing. Until then, absence from the catalogue is preferable to a misleading estimate.

## Delivery gates

1. Source and preparation-state review for each row.
2. Automated checks that IDs are unique, units and reference quantities are supported, values are finite/non-negative, provenance is present, and unknown values are not defaulted to zero.
3. Unit tests for scaling from the source reference quantity and for incomplete records.
4. UI coverage for exact match, no match, incomplete nutrients, and user-provided values.
5. Release-note and QA evidence naming the exact bundled dataset release.

The diary can ship before catalogue coverage is broad. The catalogue must remain visibly incomplete until these gates are met.
