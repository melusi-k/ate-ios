---
name: find-and-cook-recipe
description: Find a saved recipe in Ate, resolve which recipe the person means, and open it or start cook mode.
---

# Find and cook a saved recipe

Use this guidance when a request combines recipe discovery with opening or cooking a saved recipe.

## Choose the right capability

- Search Ate's saved recipes when the person asks to find, browse or choose a recipe.
- Use the open-recipe capability when the person wants to view a recipe.
- Use the start-cook-mode capability only when the person asks to begin cooking.
- Use a dinner suggestion only when the person asks what to cook or asks for Ate's recommendation; do not present a recommendation as a search result.

## Resolve the recipe carefully

- Prefer an exact, high-confidence match.
- If multiple recipes are plausible, ask which recipe the person means.
- Do not select the first result merely because it ranks highest when the match is ambiguous.
- If no suitable saved recipe exists, explain that and stop. Do not invent a recipe or imply that Ate has saved it.

## Preserve user intent

- Do not start cook mode when the person only asks to view or find a recipe.
- Do not change a recipe, shopping list or journal as an incidental part of finding or opening a recipe.
- Do not use Health-derived context to rank or select recipes unless the person has asked for a context-aware recommendation and the relevant permission and data are available.
- If a required detail is missing, ask a concise clarification rather than guessing.

## Report outcomes accurately

- Only say a recipe has opened or cook mode has started after the corresponding action reports success.
- If an action fails or Ate is not available, explain the limitation and do not claim completion.
