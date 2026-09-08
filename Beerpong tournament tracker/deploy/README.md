# Pong Cup — deploy guide (for Claude Code)

`index.html` is the complete, self-contained web app (fonts + runtime inlined). No build step. Deploying = putting this one file on a static host.

## Live
- Web (GitHub Pages, auto-deploys on push to `main`): https://gregoryverspecht.github.io/beerpong/
- iOS TestFlight public link: https://testflight.apple.com/join/ymCT9rvQ
- New iOS build: bump `version` in the root `package.json`, merge `main` into `prod`, push. The workflow builds, uploads and submits to the external group.

## Fastest: Vercel (recommended)

Tell Claude Code:

> Deploy the folder `deploy/` as a static site on Vercel. It contains a single `index.html`. Add a `vercel.json` that serves `index.html` for every path. Then give me the production URL.

Manual equivalent:
```bash
cd deploy
npm i -g vercel
vercel --prod      # follow prompts; framework = Other; output dir = .
```
`vercel.json` (optional, keeps `?table=tb1` and `?tv=1` deep links working):
```json
{ "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }] }
```

Alternatives: Netlify (drag the folder onto app.netlify.com/drop), GitHub Pages (commit `index.html` to a repo, enable Pages), Cloudflare Pages.

## After deploying
1. Open the URL on your phone → Share → **Add to Home Screen** (runs full-screen, enables background notifications on iOS).
2. Open Setup → **Sync**: status should read **CLOUD SYNC LIVE**.
3. Setup → Tables: the QR codes now point at your real URL — print them.
4. TV: open `https://<your-url>/?tv=1`.

## Supabase (already configured in the file)
Project: `https://uueoxlsrypwbqgpobuiz.supabase.co` (anon key embedded — anon keys are public by design, but the table policy below is fully open; tighten before a public event if needed).

Required table (already created):
```sql
create table tournaments (code text primary key, data jsonb not null, updated_at timestamptz default now());
alter table tournaments enable row level security;
create policy "open" on tournaments for all using (true) with check (true);
```
Sync model: one row per tournament code; the app upserts the whole state on change and polls every 2 s. Realtime publication is not required.

## Deep links
- `?table=<tableId|tableName>` → opens that table's live game in scoring mode (used by the QR codes)
- `?tv=1` → big-screen mode

## Making changes
The source of truth is `Beerpong Live.dc.html` in the design project, not this bundle. Re-export after edits and redeploy (`vercel --prod`).

## Going native later (optional)
Wrap with Capacitor (`npm i @capacitor/core @capacitor/ios`, `npx cap add ios`, copy `index.html` to `www/`) → Xcode → TestFlight. Needs a Mac + Apple Developer account.
