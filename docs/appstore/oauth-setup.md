# WanderIQ — Apple & Google Sign-In (OAuth) setup

The **client code is already done** on the web (`webapp/src/auth/webAuth.ts`
calls `supabase.auth.signInWithOAuth({ provider, options:{ redirectTo: origin }})`
and handles the returning session). The buttons start working the moment the
providers below are enabled in Supabase. These steps require YOUR Google /
Apple / Supabase accounts and secret keys — they can't be automated.

**Your Supabase project:** ref `lygkrwxrveqdhgdjtctb`
**OAuth callback URL (used everywhere below):**
`https://lygkrwxrveqdhgdjtctb.supabase.co/auth/v1/callback`
**Your web app origin:** `https://wander-iq.vercel.app`

---

## Google (easiest — do this first)

1. **Google Cloud Console** → https://console.cloud.google.com → create or pick a project.
2. **APIs & Services → OAuth consent screen**: User type **External** → fill App
   name "WanderIQ", your support email, developer contact → add scopes
   `openid`, `.../auth/userinfo.email`, `.../auth/userinfo.profile` → Save. (You
   can leave it in "Testing" and add your family emails as test users, or
   "Publish" it.)
3. **APIs & Services → Credentials → Create Credentials → OAuth client ID**:
   - Application type: **Web application**
   - **Authorized JavaScript origins:** `https://wander-iq.vercel.app`
   - **Authorized redirect URIs:** `https://lygkrwxrveqdhgdjtctb.supabase.co/auth/v1/callback`
   - Create → copy the **Client ID** and **Client secret**.
4. **Supabase Dashboard → Authentication → Providers → Google**: toggle **Enabled**,
   paste the Client ID + Client secret → **Save**.
5. Done — reload `https://wander-iq.vercel.app` and click **Continue with Google**.

---

## Apple (more involved — needs a Services ID + a signing key)

Note your **Team ID** first (Apple Developer → top-right, or Membership page; 10 chars).

1. **App ID** — Apple Developer → Certificates, Identifiers & Profiles → Identifiers →
   your **App ID `com.WanderIQ`** → enable **Sign in with Apple** capability → Save.
   (Leave "Server-to-Server Notification Endpoint" blank — Supabase doesn't use it.)
2. **Services ID** — Identifiers → **+** → **Services IDs** → e.g. `com.wanderiq.signin`,
   description "WanderIQ Sign In" → continue/register. Then open it, tick **Sign in with
   Apple** → **Configure**:
   - Primary App ID: `com.WanderIQ`
   - **Domains and Subdomains:** `lygkrwxrveqdhgdjtctb.supabase.co`  ← the SUPABASE domain (NOT the Vercel one; Supabase handles Apple's domain verification)
   - **Return URLs:** `https://lygkrwxrveqdhgdjtctb.supabase.co/auth/v1/callback`
   - Save / Done / Continue / Save.
3. **Key** — Keys → **+** → name "WanderIQ Sign in with Apple" → tick **Sign in with
   Apple** → Configure (primary App ID `com.WanderIQ`) → Register → **Download the
   `.p8`** (one chance!). Note the **Key ID** (10 chars).
4. **Generate the client-secret JWT** — on Supabase's Apple docs page
   (https://supabase.com/docs/guides/auth/social-login/auth-apple) use the
   "Generate your secret key" tool: paste your **Account/Team ID**, **Service ID**
   (`com.wanderiq.signin`), **Key ID**, and the **`.p8`** contents → it outputs a JWT.
5. **Supabase → Authentication → Providers → Apple** → Enabled:
   - **Client IDs:** `com.wanderiq.signin,com.WanderIQ`  ← Services ID (web) AND bundle ID (native iOS), comma-separated
   - **Secret Key (for OAuth):** paste the JWT from step 4
   - Save.
6. Reload the web app → **Sign in with Apple**.

> ⚠️ **App Store rule (4.8):** if the app offers Google sign-in, it must ALSO offer
> a working Sign in with Apple. So if you want social login *on the iOS app*, do
> the Apple steps too (and we re-add the iOS buttons + capability).

---

## Supabase URL configuration

**Authentication → URL Configuration:**
- Site URL = `https://wander-iq.vercel.app`
- Redirect URLs — add BOTH:
  - `https://wander-iq.vercel.app/**` (web)
  - `com.wanderiq://**` (the iOS app's redirect scheme, for Google on iOS)

---

## After you enable a provider

Tell me and I'll verify the web flow end-to-end with a browser — clicking the
button should redirect to Google/Apple and, after you authorize, land back on the
trip list signed in. (I can confirm the redirect handoff; the actual Google/Apple
login is yours to complete.)

## iOS (the buttons + entitlement are now in the app — commit 301b517)

The iOS app has the native **Sign in with Apple** button + **Continue with Google**,
the `applesignin` entitlement, and the `com.wanderiq` redirect scheme. Two extra
provider-config items are needed for iOS on top of the web steps above:

1. **Apple Developer → App ID `com.WanderIQ`**: ensure **Sign in with Apple** is
   enabled on the App ID itself (the app entitlement requests it; the capability
   must exist on the App ID, or signing/Sign-in fails).
2. **Supabase → Authentication → Providers → Apple → Client IDs**: this field must
   include the iOS **bundle ID `com.WanderIQ`** (for native id-token validation),
   IN ADDITION to the web **Services ID** `com.wanderiq.signin`. Comma-separate
   them: `com.wanderiq.signin,com.WanderIQ`.
3. Google on iOS reuses the same Supabase Google provider; just make sure
   `com.wanderiq://**` is in the Supabase Redirect URLs (above).

⚠️ Because iOS now offers Google, **a working Sign in with Apple is mandatory**
(guideline 4.8) for the App Store submission — so complete the Apple steps before
archiving. Once configured, tell me and I'll run the app to verify both buttons.
