# Runs tests/estimate-duration.test.html in headless Edge and reports the result.
# No node/npm needed - Edge ships with Windows.
$ErrorActionPreference = 'Stop'

$pages = Get-ChildItem -Path $PSScriptRoot -Filter '*.test.html' | Sort-Object Name
if (-not $pages) { Write-Error "no *.test.html found in $PSScriptRoot"; exit 1 }

$edge = @(
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $edge) { Write-Error 'No Edge or Chrome found to run the tests.'; exit 1 }

$failed = 0
foreach ($page in $pages) {
  Write-Output ''
  Write-Output ("=== " + $page.Name + " ===")

  $profileDir = Join-Path $env:TEMP ("pongcup-tests-" + [guid]::NewGuid().ToString('N'))
  $url = 'file:///' + ($page.FullName).Replace('\', '/')

  # --allow-file-access-from-files lets the page fetch() the deploy bundle off disk.
  # --host-resolver-rules keeps the run hermetic: no calls to Supabase or the QR service.
  # Edge chatters on stderr; keep stdout only rather than letting it look like a failure.
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $dom = & $edge --headless=new --disable-gpu --no-first-run --allow-file-access-from-files `
    --host-resolver-rules="MAP * ~NOTFOUND" `
    --user-data-dir="$profileDir" --virtual-time-budget=10000 --dump-dom $url 2>&1 |
    Where-Object { $_ -is [string] } | Out-String
  $ErrorActionPreference = $prev

  if (Test-Path $profileDir) { Remove-Item $profileDir -Recurse -Force -ErrorAction SilentlyContinue }

  if (-not $dom) { Write-Output 'Browser produced no output.'; $failed++; continue }

  # Strip tags so PASS/FAIL lines read cleanly in the terminal.
  $body = ($dom -split '<pre id="out">')[1]
  if ($body) {
    $body = ($body -split '</pre>')[0] -replace '<[^>]+>', ''
    Write-Output ([System.Net.WebUtility]::HtmlDecode($body)).Trim()
  }

  if ($dom -match 'RESULT: (PASS|FAIL)[^<]*') {
    Write-Output ([System.Net.WebUtility]::HtmlDecode($Matches[0]))
    if ($Matches[1] -ne 'PASS') { $failed++ }
  } else {
    Write-Output 'Could not find a test result in the page output.'
    $failed++
  }
}

Write-Output ''
if ($failed) { Write-Output "$failed test file(s) FAILED"; exit 1 }
Write-Output 'All test files passed.'
exit 0
