---
name: find-and-cook-recipe
description: Find a saved recipe in Ate and start cook mode for the specific recipe the person chooses.
---

# Find and cook a saved recipe

Use this skill when a person wants to find one of their saved Ate recipes and then begin cooking it.

1. Call the **Find saved recipes** tool first, using the person's recipe name, ingredients, cuisine, or other search terms.
2. If no recipes are returned, explain that Ate did not find a saved match. Do not invent a recipe or switch to a dinner recommendation.
3. If more than one plausible recipe is returned, ask the person which exact recipe they mean. Do not choose the first result just because it ranks highest.
4. Only after the person has identified a specific recipe, call **Start cook mode for a saved recipe** with that recipe's exact title.
5. If the start-cook-mode tool reports that it could not identify the recipe confidently, ask the person to clarify and do not retry with a guessed alternative.
6. Do not start cook mode when the person only asks to search, browse, or view recipes. Use the appropriate existing open-recipe capability when they ask to view a recipe.
7. Do not use a health-informed dinner pick, infer a recipe from Health data, change a recipe, add shopping-list items, or create a Journal entry as part of this workflow.
8. Both tools require device authentication because recipe names are private library content. If authentication is not completed, stop and explain that the action was not performed.
9. Report success only after the tool confirms that cook mode is starting. If a tool fails, report the failure without claiming the workflow completed.

The tools validate their own inputs and enforce their own authentication requirements. This guidance helps Siri choose and coordinate them; it does not guarantee a fixed execution order.
