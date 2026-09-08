<#
.SYNOPSIS
  Re-applies local fixes to a fresh index.html export from the design project.

  The exporter packs the app HTML as a JSON string inside
  <script type="__bundler/template">. This script decodes it, applies exact
  string patches, re-encodes it (escaping "/" as "\/" so a literal
  "</script>" can never terminate the outer tag), and validates the result.

  Idempotent: patches already present are skipped. A missing anchor fails
  loudly so a changed export never gets a half-applied fix.

.USAGE
  powershell -File scripts/patch-export.ps1            # patches deploy/index.html
  powershell -File scripts/patch-export.ps1 -Path x.html
#>
param(
  [string]$Path = (Join-Path $PSScriptRoot "..\Beerpong tournament tracker\deploy\index.html")
)
$ErrorActionPreference = 'Stop'
$Path = (Resolve-Path $Path).Path

# --- patches: anchor -> replacement (anchor must occur exactly once) ---------
$patches = @(
  @{
    name = 'iOS: 16px form fields so Safari does not auto-zoom'
    find = 'input,select,button{font-family:inherit}'
    repl = 'input,select,button{font-family:inherit} @supports (-webkit-touch-callout: none){input,select,textarea{font-size:16px !important}}'
    done = '@supports (-webkit-touch-callout: none){input,select,textarea{font-size:16px !important}}'
  },
  @{
    name = 'timer: mkGame carries endsAt'
    find = "status: o.b ? 'sched' : 'bye', table: null, left: 0, paused: false,"
    repl = "status: o.b ? 'sched' : 'bye', table: null, left: 0, endsAt: null, paused: false,"
    done = "left: 0, endsAt: null, paused: false,"
  },
  # upgrade steps for files patched by an earlier version of this script (optional: skipped on fresh exports)
  @{
    name = 'timer v1->v2: migrated flag'
    optional = $true
    find = 'let changed = false; const now = Date.now();'
    repl = 'let changed = false, migrated = false; const now = Date.now();'
    done = 'let changed = false, migrated = false;'
  },
  @{
    name = 'timer v1->v2: mark legacy games as migrated'
    optional = $true
    find = 'if (!g.endsAt) return { ...g, endsAt: now + Math.max(0, g.left) * 1000 };'
    repl = 'if (!g.endsAt) { migrated = true; return { ...g, endsAt: now + Math.max(0, g.left) * 1000 }; }'
    done = 'if (!g.endsAt) { migrated = true;'
  },
  @{
    name = 'timer: tick derives left from wall-clock endsAt'
    find = @'
      let changed = false;
      let games = st.games.map(g => {
        if (g.status !== 'live' || g.paused) return g; changed = true;
        const left = g.left - 1;
        if (left > 0) return { ...g, left };
'@
    repl = @'
      let changed = false, migrated = false; const now = Date.now();
      let games = st.games.map(g => {
        if (g.status !== 'live' || g.paused) return g; changed = true;
        // Wall-clock anchored: survives background, refresh and multi-device sync.
        // endsAt is the source of truth while running; left is derived for display.
        if (!g.endsAt) { migrated = true; return { ...g, endsAt: now + Math.max(0, g.left) * 1000 }; }
        const left = Math.max(0, Math.ceil((g.endsAt - now) / 1000));
        if (left === g.left) return g;
        if (left > 0) return { ...g, left };
'@
    done = 'const left = Math.max(0, Math.ceil((g.endsAt - now) / 1000));'
  },
  @{
    name = 'timer: games started before the fix push their endsAt once'
    find = '      if (!changed) { this.tickOnly = false; return null; }'
    repl = @'
      if (!changed) { this.tickOnly = false; return null; }
      if (migrated) this.tickOnly = false; // sync endsAt for games that were live before the timer fix
'@
    done = 'if (migrated) this.tickOnly = false;'
  },
  @{
    name = 'timer: start sets endsAt'
    find = "status: 'live', table: t.id, left: t.timerMin * 60, ca: s.cups, cb: s.cups, hist: [], hits: {} }"
    repl = "status: 'live', table: t.id, left: t.timerMin * 60, endsAt: Date.now() + t.timerMin * 60000, ca: s.cups, cb: s.cups, hist: [], hits: {} }"
    done = "endsAt: Date.now() + t.timerMin * 60000"
  },
  @{
    name = 'timer: pause freezes left, resume re-anchors endsAt'
    find = "togglePause: () => this.upd(id, x => ({ ...x, paused: !x.paused })),"
    repl = "togglePause: () => this.upd(id, x => x.paused ? { ...x, paused: false, endsAt: x.status === 'live' ? Date.now() + Math.max(0, x.left) * 1000 : null } : { ...x, paused: true, left: x.endsAt && x.status === 'live' ? Math.max(0, Math.ceil((x.endsAt - Date.now()) / 1000)) : x.left, endsAt: null }),"
    done = "togglePause: () => this.upd(id, x => x.paused ?"
  },
  @{
    name = 'timer: +1 min extends endsAt'
    find = "addMinute: () => this.upd(id, x => ({ ...x, left: x.left + 60, status: x.status === 'sudden' ? 'live' : x.status })),"
    repl = "addMinute: () => this.upd(id, x => { const rem = x.endsAt && !x.paused && x.status === 'live' ? Math.max(0, Math.ceil((x.endsAt - Date.now()) / 1000)) : x.left; const left = rem + 60; return { ...x, left, status: x.status === 'sudden' ? 'live' : x.status, endsAt: x.paused ? null : Date.now() + left * 1000 }; }),"
    done = "addMinute: () => this.upd(id, x => { const rem ="
  },
  @{
    name = 'sync: keep local endsAt when an older client sends state without it'
    find = 'persistData() { const d = {};'
    repl = @'
mergeRemote(d) {
    // Clients running the pre-timer-fix build push games without endsAt. Keep ours
    // for a running game so their stale "left" cannot restart the clock.
    if (!d || !Array.isArray(d.games)) return d;
    const mine = this.state.games || [];
    return { ...d, games: d.games.map(g => { const l = mine.find(x => x.id === g.id); return l && l.endsAt && !g.endsAt && g.status === 'live' && !g.paused ? { ...g, endsAt: l.endsAt } : g; }) };
  }
  persistData() { const d = {};
'@
    done = 'mergeRemote(d) {'
  },
  @{
    name = 'sync: initial cloud pull goes through mergeRemote'
    find = 'this.setState(row.data)'
    repl = 'this.setState(this.mergeRemote(row.data))'
    done = 'this.setState(this.mergeRemote(row.data))'
  },
  @{
    name = 'sync: cloud poll goes through mergeRemote'
    find = 'this.setState(r.data)'
    repl = 'this.setState(this.mergeRemote(r.data))'
    done = 'this.setState(this.mergeRemote(r.data))'
  },
  @{
    name = 'sync: same-device broadcast goes through mergeRemote'
    find = 'this.setState(m.data)'
    repl = 'this.setState(this.mergeRemote(m.data))'
    done = 'this.setState(this.mergeRemote(m.data))'
  },
  @{
    name = 'tables: a team already playing cannot be started at another table'
    find = 'const startOpts = g => freeTables.map('
    repl = @'
const busyTeams = new Set(st.games.filter(g => g.status === 'live' || g.status === 'sudden').flatMap(g => [g.a, g.b]));
    const teamBusy = g => busyTeams.has(g.a) || busyTeams.has(g.b);
    const startOpts = g => teamBusy(g) ? [] : freeTables.map(
'@
    done = 'const startOpts = g => teamBusy(g) ? [] : freeTables.map('
  },
  @{
    name = 'tables: "up next" is the first scheduled game whose teams are free'
    find = "const nextGames = st.games.filter(g => g.status === 'sched').slice(0, 8).map((g, i) => { const isCall = i === 0 && freeTables.length > 0; return { ...deco(g), startOptions: startOpts(g), isCall,"
    repl = "const callIdx = st.games.filter(g => g.status === 'sched').slice(0, 8).findIndex(g => !teamBusy(g)); const nextGames = st.games.filter(g => g.status === 'sched').slice(0, 8).map((g, i) => { const isCall = i === callIdx && freeTables.length > 0; return { ...deco(g), startOptions: startOpts(g), isCall, teamBusy: teamBusy(g),"
    done = "const isCall = i === callIdx && freeTables.length > 0;"
  },
  @{
    name = 'tables: TV call-up follows the same rule'
    find = 'const callGame = freeTables.length && nextGames.length ? nextGames[0] : null;'
    repl = 'const callGame = freeTables.length ? nextGames.find(g => g.isCall) || null : null;'
    done = 'nextGames.find(g => g.isCall)'
  },
  @{
    name = 'tables: call-up notification skips games whose team is still playing'
    find = "const free = st.tables.find(t => !busy.has(t.id)), next = st.games.find(g => g.status === 'sched');"
    repl = @'
const busyTeams = new Set(st.games.filter(g => g.status === 'live' || g.status === 'sudden').flatMap(g => [g.a, g.b]));
    const free = st.tables.find(t => !busy.has(t.id)), next = st.games.find(g => g.status === 'sched' && !busyTeams.has(g.a) && !busyTeams.has(g.b));
'@
    done = "next = st.games.find(g => g.status === 'sched' && !busyTeams.has(g.a)"
  },
  @{
    name = 'tables: waiting games show why they cannot start'
    find = @'
          <div style="font-size:11px;color:#a8a194;letter-spacing:.1em">{{ g.stageLabel }}</div>
        </div>
        <div style="display:flex;gap:6px;flex-wrap:wrap;justify-content:flex-end">
          <sc-for list="{{ g.startOptions }}" as="o" hint-placeholder-count="2">
'@
    repl = @'
          <div style="font-size:11px;color:#a8a194;letter-spacing:.1em">{{ g.stageLabel }}</div>
          <sc-if value="{{ g.teamBusy }}" hint-placeholder-val="{{ false }}"><div style="font-size:10px;font-weight:700;letter-spacing:.14em;color:#ff7a6b">TEAM STILL PLAYING</div></sc-if>
        </div>
        <div style="display:flex;gap:6px;flex-wrap:wrap;justify-content:flex-end">
          <sc-for list="{{ g.startOptions }}" as="o" hint-placeholder-count="2">
'@
    done = 'TEAM STILL PLAYING'
  },
  @{
    name = 'timer: reopen clears endsAt (game reopens paused)'
    find = "status: x.left > 0 ? 'live' : 'sudden', paused: true, reason: '' }"
    repl = "status: x.left > 0 ? 'live' : 'sudden', paused: true, endsAt: null, reason: '' }"
    done = "paused: true, endsAt: null, reason: '' }"
  }
)

# --- helpers ----------------------------------------------------------------
function Encode-JsonString([string]$s) {
  $sb = New-Object System.Text.StringBuilder ($s.Length + 4096)
  [void]$sb.Append('"')
  foreach ($ch in $s.ToCharArray()) {
    switch ($ch) {
      '"'  { [void]$sb.Append('\"') }
      '\'  { [void]$sb.Append('\\') }
      '/'  { [void]$sb.Append('\/') }
      "`n" { [void]$sb.Append('\n') }
      "`r" { [void]$sb.Append('\r') }
      "`t" { [void]$sb.Append('\t') }
      default {
        if ([int]$ch -lt 0x20) { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) } else { [void]$sb.Append($ch) }
      }
    }
  }
  [void]$sb.Append('"')
  $sb.ToString()
}

function Count-Occurrences([string]$hay, [string]$needle) {
  $n = 0; $i = 0
  while (($i = $hay.IndexOf($needle, $i, [System.StringComparison]::Ordinal)) -ge 0) { $n++; $i += $needle.Length }
  $n
}

# --- decode -----------------------------------------------------------------
$html = [System.IO.File]::ReadAllText($Path)
$rx = [regex]::new('(<script type="__bundler/template"[^>]*>)(.*?)(</script>)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$m = $rx.Match($html)
if (-not $m.Success) { throw "No __bundler/template script found in $Path" }
$json = $m.Groups[2].Value
# keep the whitespace the exporter puts around the JSON so line-based diffs stay readable
$lead  = [regex]::Match($json, '^\s*').Value
$trail = [regex]::Match($json, '\s*$').Value
if ($json.Trim() -match "[\x00-\x1F]") { Write-Warning "template JSON contains raw control characters (browsers will reject it) - fixing by re-encoding" }
$tpl = $json | ConvertFrom-Json
if ($tpl -isnot [string]) { throw "template did not decode to a string" }

# --- patch ------------------------------------------------------------------
$applied = 0
foreach ($p in $patches) {
  $find = $p.find -replace "`r`n", "`n"
  $repl = $p.repl -replace "`r`n", "`n"
  if ((Count-Occurrences $tpl $p.done) -gt 0) { Write-Host "  = already: $($p.name)"; continue }
  $c = Count-Occurrences $tpl $find
  if ($c -eq 0 -and $p.optional) { Write-Host "  - n/a:     $($p.name)"; continue }
  if ($c -ne 1) { throw "anchor for '$($p.name)' found $c times (expected 1). The export changed; update scripts/patch-export.ps1." }
  $tpl = $tpl.Replace($find, $repl)
  Write-Host "  + applied: $($p.name)"
  $applied++
}

# --- encode + write ---------------------------------------------------------
$newJson = Encode-JsonString $tpl
if ($newJson -match "[\x00-\x1F]") { throw "encoder left raw control characters" }
$roundTrip = $newJson | ConvertFrom-Json
if ($roundTrip -ne $tpl) { throw "round-trip mismatch after encoding" }
$out = $html.Substring(0, $m.Groups[2].Index) + $lead + $newJson + $trail + $html.Substring($m.Groups[2].Index + $m.Groups[2].Length)
[System.IO.File]::WriteAllText($Path, $out, [System.Text.UTF8Encoding]::new($false))
Write-Host "OK: $applied patch(es) applied, template re-encoded ($($newJson.Length) chars) -> $Path"
