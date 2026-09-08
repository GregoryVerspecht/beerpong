# Pong Cup — Beerpong tournament tracker

Single-file web app: group stage → knockout, live scoring on multiple tables, timers, player stats, TV mode, multi-device sync via Supabase.

## Live
- Web (GitHub Pages, auto-deploys on push to `main`): https://gregoryverspecht.github.io/beerpong/
- iOS TestFlight public link: https://testflight.apple.com/join/ymCT9rvQ

## Deploy

**GitHub Pages** — already set up: `.github/workflows/pages.yml` publishes this folder on every push to `main`.

**iOS (TestFlight)** — bump `version` in the root `package.json`, merge `main` into `prod`, push. `.github/workflows/ios-release.yml` builds with Capacitor, uploads and submits to the external group.

**Vercel / Netlify** — import the repo, no build step, output dir `.` (`vercel.json` included).

## Usage
- Phone: open the URL → Share → *Add to Home Screen*.
- TV: `?tv=1`
- Table QR codes (Setup → Tables) open `?table=<id>` straight into scoring.
- Setup → Sync shows cloud status; join another tournament by its 6-letter code.

## Supabase
Configured in `index.html` (URL + anon key, editable in Setup → Sync → Configure). Table:
```sql
create table tournaments (code text primary key, data jsonb not null, updated_at timestamptz default now());
alter table tournaments enable row level security;
create policy "open" on tournaments for all using (true) with check (true);
```

## Source
`index.html` is a bundled export from the design project; edit there and re-export, or edit `index.html` directly (it is plain HTML + JS).

**After every re-export, run the patch script** — it re-applies fixes that live only in this repo until they are ported to the design source:

```powershell
powershell -File scripts/patch-export.ps1
```

It decodes the bundle, applies the patches below (skipping ones already present), re-encodes it safely and validates the JSON. A missing anchor means the export changed around that spot: update the anchor in the script rather than skipping it.

Patches it carries:
- iOS: form fields at 16px so Safari does not auto-zoom on focus.
- Timer: games store a wall-clock `endsAt`; `left` is derived from it each tick. Survives backgrounding, refresh and multi-device sync. Pause freezes `left` and clears `endsAt`; resume, start and +1 min re-anchor it.
