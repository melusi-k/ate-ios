# Files picker Cancel: device-only

Permanent boundary: verify the real Files picker manually on iPhone, not in simulator CI. Device result is pending, not a claimed pass. The existing automated method is retained unchanged for reference; the Journal CI selection keeps it explicitly skipped and no longer runs an advisory diagnostic for it.

## Device test

On the installed candidate, open Settings → Food diary. Note the current meals for the selected day and any existing error. Scroll to Meal backup recovery → Restore your JSON meal backup. When the actual Files picker appears, tap Cancel without choosing a file.

Expected: return to the same Food diary, with no new import error, no Review meal backup sheet, and no added meal. The existing meals stay unchanged. Capture the diary before opening Files and after Cancel, and record build number and result. No JSON sample or backup file is needed because nothing is selected or imported. Do not confirm an import.

Why: cancelling file selection is no action. It must not read or import a backup, report a new import failure, or add a meal. A real device checks the system picker handoff that simulator automation did not reliably expose.

Source-verified path: SettingsView's Food diary link opens Route.nutritionDiary. CanonicalNutritionDiaryView shows Meal backup recovery and Restore your JSON meal backup; MealBackupDocumentPicker returns nil on cancellation, and that handler exits before file reads/review/error updates. This is the meal-backup picker, not Settings' separate recipe import.
