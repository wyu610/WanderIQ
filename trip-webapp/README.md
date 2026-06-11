# 2026 暑假中国行清单 — Family Trip Web App

A self-contained web app (PWA). Works on iPhone, iPad, Android — everyone opens the same URL.
Offline-capable once installed. Optional family sync via a free Supabase table.

## 1. Deploy to Vercel (one time)

**Option A — Vercel CLI (fastest, ~2 minutes)**
1. Install Node.js if you don't have it (nodejs.org).
2. Open Terminal in this folder and run:
   ```
   npx vercel
   ```
   Log in when prompted, accept the defaults (it auto-detects a static site).
3. Run `npx vercel --prod` to get your permanent URL, e.g. `https://china-trip.vercel.app`.

**Option B — GitHub + Vercel (no command line)**
1. Create a free GitHub account → New repository → "uploading an existing file" → drag all files in this folder → Commit.
2. Go to vercel.com → Add New Project → Import that repository → Deploy. Done.

**Option C — Netlify Drop (easiest of all, if Vercel isn't required)**
Go to https://app.netlify.com/drop and drag this whole folder onto the page. Instant URL.

## 2. Set up family sync (one time, one person)

Without this step the app still fully works — but each device keeps its own checkmarks.
With it, the whole family shares one live checklist.

1. Go to https://supabase.com → your project (or create a free one).
2. Left sidebar → **SQL Editor** → paste the contents of `setup.sql` → **Run**.
3. Left sidebar → **Settings → API** → copy the **Project URL** and the **anon public** key.
4. Open your deployed app → 清单提醒 tab → 家庭共享同步 card → paste both → **保存并测试连接**.
5. Tap **☁ 开启家庭同步**, then **🔗 复制家庭邀请链接** and send it to the family group chat.
6. Family members open the invite link once (config applies automatically), then tap 开启家庭同步.

Note: the anon key is designed to be public, but anyone holding the invite link can read/edit
the checklist — share it only with family and don't put passport numbers etc. in the list.

## 3. Install like an app

- **iPhone / iPad (Safari):** open the URL → Share button → **Add to Home Screen**.
- **Android (Chrome):** menu → **Add to Home screen** / **Install app**.

It launches full-screen with its own icon, and keeps working offline (sync resumes when online).

## Heads-up for mainland China (July trip)

`*.vercel.app` and `supabase.co` can be unreliable inside mainland China on local networks.
Two easy mitigations:
- If your Canadian phones use **roaming data**, traffic routes through Canada and everything works normally.
- The app is **offline-capable**: install it to the home screen before relying on hotel Wi-Fi; checkmarks
  save locally and sync catches up whenever connectivity allows. Hong Kong is unaffected.

## Files

- `index.html` — the entire app
- `manifest.webmanifest`, `sw.js`, `icon-*.png`, `apple-touch-icon.png` — PWA install + offline support
- `setup.sql` — one-time Supabase table setup for family sync
