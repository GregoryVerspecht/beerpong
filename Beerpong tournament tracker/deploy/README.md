# Pong Cup — Beerpong tournament tracker

Single-file web app: group stage → knockout, live scoring on multiple tables, timers, player stats, TV mode, multi-device sync via Supabase.

## Live
- Web (GitHub Pages, auto-deploys on push to `main`): https://pong-cup.gv-tech.eu/ (custom domain; falls back to https://gregoryverspecht.github.io/beerpong/ until DNS for `pong-cup.gv-tech.eu` is verified)
- iOS TestFlight public link: https://testflight.apple.com/join/ymCT9rvQ

## Deploy

**GitHub Pages** — already set up: `.github/workflows/pages.yml` publishes this folder on every push to `main`.

**iOS (TestFlight)** — bump `version` in the root `package.json`, merge `main` into `prod`, push. `.github/workflows/ios-release.yml` builds with Capacitor, uploads and submits to the external group.

**Vercel / Netlify** — import the repo, no build step, output dir `.` (`vercel.json` included).

**Custom domain (`pong-cup.gv-tech.eu`)** — set in the repo's Pages settings and in the `CNAME` file in this folder. At the DNS provider for `gv-tech.eu`, add:
```
CNAME   pong-cup   gregoryverspecht.github.io.
```
GitHub verifies the record and provisions HTTPS automatically once it resolves (can take a few minutes up to ~24h). Until then the site is reachable at both the custom domain (HTTP only) and the `github.io` URL above; HTTPS enforcement turns on by itself once the cert is issued.

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
`index.html` is a bundled export from the design project (`Beerpong Live.dc.html`); edit there and re-export, or edit `index.html` directly (it is plain HTML + JS).

As of the September 2026 redesign (Home tab, splash screen, iOS-style tab bar, vertical bracket flow, per-cup tap scoring), the fixes below live in the design source itself, so a fresh export needs no post-processing:
- iOS: form fields at 16px so Safari does not auto-zoom on focus.
- Timer: games store a wall-clock `endsAt`; `left` is derived from it each tick. Survives backgrounding, refresh and multi-device sync. Pause freezes `left` and clears `endsAt`; resume, start and +1 min re-anchor it. Incoming state from an older client keeps the local `endsAt`.
- Schedule: group games are generated in round-robin (circle) order with rounds interleaved across groups, so consecutive games never wait on the same team. Applies to newly generated schedules (Start tournament / Regenerate).
- Tables: a team that is in a live game cannot be started at another table. "Up next", the TV call-up and the notification pick the first scheduled game whose teams are both free; waiting games show "TEAM STILL PLAYING".

`scripts/patch-export.ps1`, which used to re-apply these after every export, has been retired — re-running it against a current export would either no-op or throw ("anchor not found") since the text it searches for no longer matches. If a future export ever drops one of these behaviors again, patch `index.html` directly rather than reviving the script.

Before shipping any fresh export, sanity-check its `<title>` (should read "Pong Cup · Beerpong Tournament") and the loading-screen background (`body`/`#__bundler_thumbnail`, should be `#0c0b09`) — the exporter has occasionally reset these to generic defaults ("Bundled Page" / light background) without a corresponding product change.
