# WanderIQ 1.0 (2) — App Store submission notes (v2, account-based)

The v2 build adds accounts + cloud sync, so the **App Privacy** section changes from
v1's "Data Not Collected." Below are the exact answers to enter in App Store Connect,
plus the App Review notes. Listing copy (name/subtitle/description/keywords) is in
`listing.md`.

Verified in code (2026-06-15): **no** location/GPS, **no** analytics/tracking SDKs,
**no** ads. Data lives in Supabase (Postgres). The only things collected are the
account email, the account's user id, and the trips the user creates.

---

## App Privacy questionnaire (ASC → App Privacy → Edit)

**"Do you or your third-party partners collect data from this app?" → Yes.**

Declare these three data types. For every one: **Linked to the user's identity = Yes**
(it's tied to their account) and **Used for tracking = No** (no cross-app/advertising
tracking; ATT not used).

| Apple data category | Data type | Purpose | Linked | Tracking |
|---|---|---|---|---|
| Contact Info | **Email Address** | App Functionality | Yes | No |
| User Content | **Other User Content** (trips, checklist items, notes) | App Functionality | Yes | No |
| Identifiers | **User ID** (account id) | App Functionality | Yes | No |

- **Purpose** for all three: select **App Functionality** only. Do NOT check
  Analytics, Product Personalization, Advertising, or Developer's Marketing.
- **"Used to Track You"**: **None** — leave every "used for tracking" box unchecked.
  (The app has no ad/analytics SDKs, so no ATT prompt and no tracking declaration.)
- Do NOT declare: Location, Health, Financial, Browsing History, Search History,
  Contacts, Photos, Diagnostics — none are collected.

**Privacy Policy URL (required):** ⚠️ the existing `trip-webapp/privacy.html` is
CloudKit-era and now inaccurate (it predates accounts/Supabase). You need a public
privacy-policy URL that reflects: we collect email + trip content, store/process it
via Supabase, use it only to sync and share trips, and the user can delete their
data. (Ask me to rewrite + host this on the web app when you're ready — it's a
~10-minute follow-up; the field is mandatory before you can submit.)

---

## App Review notes (ASC → Version → App Review Information → Notes)

WanderIQ is account-gated (it syncs personal trips across devices), so reviewers
need a working login. Create a throwaway demo account first — in the app tap
**Sign Up** with any email (email confirmation is disabled), or reuse one you
control — then paste its credentials below.

```
WanderIQ requires a free account to sync trips across devices and share them.

Demo account:
  Email:    <demo email you created>
  Password: <demo password>

Notes for the reviewer:
- Sign in with the credentials above (or tap "Sign Up" to make a new account —
  email confirmation is disabled, so sign-up is immediate).
- After sign-in you'll see the trip list. Tap a trip to see Prep / Itinerary /
  Packing checklists; tap a row to check it off.
- Tap "+" to create a trip. The person icon (top-right of a trip) invites another
  person by email as viewer or editor.
- Export/Import: inside a trip, the Export menu saves the trip as JSON or CSV;
  on the trip list, Import reads a JSON/CSV file as a new trip.
- The same account also works on the web app (https://wander-iq.vercel.app).
- No special hardware required; everything works in the simulator.
```

Also set: **Sign-In required = Yes**, and provide the demo credentials in the
dedicated username/password fields (in addition to the notes).

---

## Pre-submit checklist

- [ ] Build **1.0 (2)** processed in TestFlight (Phase 2 upload).
- [ ] Tested signed-in on a real device: web-created trip `tes 123` appears (sync ✓).
- [ ] App Privacy updated per the table above (no longer "Data Not Collected").
- [ ] Privacy Policy URL set (rewrite the stale one first — see ⚠️ above).
- [ ] Screenshots reflect v2 (login + sharing) — optional refresh.
- [ ] Listing copy from `listing.md` pasted (EN + zh-Hans), Category = Travel,
      Age 4+, Price Free.
- [ ] App Review notes + demo account filled.
- [ ] Build 1.0 (2) attached to the 1.0 App Store version → **Submit for Review**.
- Export compliance: already handled (ITSAppUsesNonExemptEncryption=false) — no prompt.
