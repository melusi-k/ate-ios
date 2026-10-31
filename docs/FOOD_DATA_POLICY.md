# Food data policy (#179)

## Sources and rights
- Initial source: USDA FoodData Central, SR Legacy release 2018-04, official dataset (https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip). Licence: CC0/public domain per https://fdc.nal.usda.gov/api-guide/ ("not copyrighted... No permission is needed"); records carry FoodData Central attribution in their source fields.
- South African source (SAFOODS): usage rights are UNCONFIRMED as of 2026-10-31. No SAFOODS data is used. The issue #179 criterion covering a South African source and the documented source-priority policy remains OPEN until rights are confirmed and the policy is updated; this document records the interim state: USDA SR Legacy is the only source, as a fallback-first start while SA-source rights are pending.

## Records
- Record names are the exact source descriptions. Preparation state, drained/canned/unsalted status and nutrient values are preserved exactly as published, per 100 g.
- Missing source nutrients stay nil; they are never estimated.

## Aliases and matching
- Matching is exact on normalized names/aliases only (no fuzzy matching), enforced by RecipeNutritionCalculator.
- An alias may only reorder or simplify the record's own source terms for the same food in the same preparation state, and must preserve every nutritionally material qualifier (e.g. degermed/unenriched, flesh-and-skin, meat-only, lean/fat ratio, drained, with-bone, vitamin-D-added, sunflower-oil subtype). If a qualifier cannot be preserved, the alias is removed, not loosened.
- Aliases carry an explicit state word (raw/dry/canned/drained) wherever the source distinguishes states. For dry legumes only, "dry" denotes the same as-sold uncooked state as the source's "raw".
- No dish names, no SA-language names, no cross-food or cross-state aliases. SA names (pap, samp, morogo, amasi, boerewors, mageu, rooibos and similar) are added only with owning-source evidence, one at a time, in reviewed PRs.
- Unmapped ingredients surface as incomplete; nutrition values are never fabricated.

## Maintenance
- Every catalogue change ships with CatalogueIntegrityTests passing: verified+rights flags, finite values, unique IDs and unique normalized names/aliases, material-qualifier preservation.
