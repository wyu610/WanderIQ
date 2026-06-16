# WanderIQ 2.1 (1) — App Store submission notes (v2, account-based)

> Public release ships as **version 2.1, build 1**. (1.0 only reached TestFlight.)
> In App Store Connect, create a **new 2.1 version** and attach the 2.1 (1) build.

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

**Privacy Policy URL (required):** ✅ use **`https://wander-iq.vercel.app/privacy.html`**
— the v2-accurate, bilingual policy (email + trip content via Supabase, used only
to sync/share, in-app deletion). Already live.

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
  email confirmation is disabled, so sign-up is immediate). Sign in with Apple
  and Continue with Google are also available.
- After sign-in you'll see the trip list. Tap a trip to see Prep / Itinerary /
  Packing checklists; tap a row to check it off.
- Tap "+" to create a trip. The person icon (top-right of a trip) invites another
  person by email as viewer or editor.
- Export/Import: inside a trip, the Export menu saves the trip as JSON or CSV;
  on the trip list, Import reads a JSON/CSV file as a new trip.
- Account deletion: the account menu (person icon, top-left of the trip list) has
  "Delete Account", which permanently removes the account and all data.
- The same account also works on the web app (https://wander-iq.vercel.app).
- No special hardware required; everything works in the simulator.
```

Also set: **Sign-In required = Yes**, and provide the demo credentials in the
dedicated username/password fields (in addition to the notes).

---

## Pre-submit checklist

- [ ] Archive + upload **2.1 (1)**; confirm it processes in TestFlight.
- [ ] Tested signed-in on a real device: sync works; Apple + Google sign-in work.
- [ ] App Privacy updated per the table above (no longer "Data Not Collected").
- [ ] Privacy Policy URL set → `https://wander-iq.vercel.app/privacy.html`.
- [ ] Screenshots reflect v2 (login + sharing) — optional refresh.
- [ ] Listing copy from `listing.md` pasted (EN + zh-Hans), Category = Travel,
      Age 4+, Price Free.
- [ ] App Review notes + demo account filled.
- [ ] Create a **2.1** version in ASC, attach build 2.1 (1) → **Submit for Review**.
- Export compliance: already handled (ITSAppUsesNonExemptEncryption=false) — no prompt.
