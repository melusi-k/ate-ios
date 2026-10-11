# Health data privacy

_Last updated: 11 October 2026_

This page covers how ate uses **Apple Health (HealthKit)** and **Journaling Suggestions**. It's part of the [Privacy Policy](privacy.html).

## What ate reads
Only if you tap **Connect Apple Health** and allow it in Apple's permission sheet, ate can read:

| Data | Why |
|---|---|
| Sleep analysis | "Rough night" suggestions, like lighter or comforting meals |
| Step count | Daily activity on Insights |
| Active energy | Matching recipe portions to how active you've been |
| Workouts | Post-workout recipe suggestions |

ate **never writes** to Apple Health. You choose each type, and you can turn any of them off in **iOS Settings › Health › Data Access & Devices › ate**.

## Where it goes
- Health data is **read and processed on your iPhone only.**
- It's **never** uploaded to Supabase, synced to your account, included in shared recipes, sent to any AI service, or given to anyone else.
- It's **never** used for advertising, marketing, data mining or profiling, and never sold. (This is also an Apple rule for HealthKit apps.)
- ate keeps only the Insights it works out, such as "slept under 6 hours", on your device. They're deleted when you remove local data or delete the app.

## Journaling Suggestions and the Insights journal
- If enabled, Apple's Journaling Suggestions picker lets **you** choose a moment, such as a workout or a place you visited. ate gets only the moment you pick, never the rest.
- Saved moments and journal entries (including ones you create with Siri, "save a journal entry in ate") stay in **ate's own journal on your device**. They're not written to Apple's Journal app and not synced.
- This feature is switched off until Apple grants the entitlement.

## Not medical advice
Insights and suggestions are general food and cooking ideas, not medical advice or a diagnosis.

## Your choices
- Disconnect: iOS Settings › Health › Data Access & Devices › ate › Turn off all.
- Delete what ate worked out: delete the app (this removes Insights and journal entries).
- Questions: **melusi.l.k@gmail.com**.

> ⚖️ **Lawyer review needed:** health information is "special personal information" under POPIA (s26–33) and special-category data under GDPR (art. 9). Confirm the consent wording and whether a prior authorisation or DPIA is needed.
