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

## Apple (more involved — optional for web; required on iOS if you ship Apple sign-in)

Apple web sign-in ("Sign in with Apple" via OAuth) needs a Services ID + a key:

1. **Apple Developer → Certificates, Identifiers & Profiles → Identifiers**
   - Ensure your **App ID** `com.WanderIQ` has **Sign in with Apple** capability enabled.
   - **+ → Services IDs** → create one, e.g. `com.wanderiq.signin`, description "WanderIQ Web".
     Enable **Sign in with Apple** → **Configure**:
     - Primary App ID: `com.WanderIQ`
     - **Domains:** `wander-iq.vercel.app`
     - **Return URLs:** `https://lygkrwxrveqdhgdjtctb.supabase.co/auth/v1/callback`
2. **Keys → +** → name it, enable **Sign in with Apple** → Configure (primary App ID) →
   **Register** → **download the `.p8` file** (one-time). Note the **Key ID** and your **Team ID**.
3. **Supabase → Authentication → Providers → Apple** → Enabled → enter:
   - **Client IDs / Services ID:** `com.wanderiq.signin`
   - **Team ID**, **Key ID**, and paste the **`.p8` contents** (Supabase mints the
     client-secret JWT for you). Save.
4. Reload the web app → **Sign in with Apple**.

> ⚠️ **App Store rule (4.8):** if the app offers Google sign-in, it must ALSO offer
> a working Sign in with Apple. So if you want social login *on the iOS app*, do
> the Apple steps too (and we re-add the iOS buttons + capability).

---

## Supabase URL configuration (already set — just confirm)

**Authentication → URL Configuration:** Site URL = `https://wander-iq.vercel.app`,
and `https://wander-iq.vercel.app/**` in Redirect URLs. (Set earlier; required so
the OAuth round-trip returns to the app.)

---

## After you enable a provider

Tell me and I'll verify the web flow end-to-end with a browser — clicking the
button should redirect to Google/Apple and, after you authorize, land back on the
trip list signed in. (I can confirm the redirect handoff; the actual Google/Apple
login is yours to complete.)

## iOS

The iOS app is currently **email-only** (we removed the Apple/Google buttons for
the App Store launch). To put social sign-in on iOS too, say so and I'll re-add:
native **Sign in with Apple** (ASAuthorization → `signInWithIdToken`), the
**Continue with Google** button, the `applesignin` entitlement, and the
`com.wanderiq` redirect scheme — then bump the build. (Requires the Apple steps
above, and Apple Sign-In becomes mandatory per 4.8.)
