#!/usr/bin/env bash
# Runs every tests/*.test.html in headless Chromium and reports the result.
# Linux/macOS counterpart of run-tests.ps1 (which uses Edge on Windows).
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

browser=""
for candidate in \
  "${CHROME:-}" \
  /opt/pw-browsers/chromium-*/chrome-linux/chrome \
  "$(command -v chromium 2>/dev/null)" \
  "$(command -v chromium-browser 2>/dev/null)" \
  "$(command -v google-chrome 2>/dev/null)" \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then browser="$candidate"; break; fi
done

if [ -z "$browser" ]; then echo "No Chromium or Chrome found to run the tests." >&2; exit 1; fi

failed=0
shopt -s nullglob
pages=("$here"/*.test.html)
if [ ${#pages[@]} -eq 0 ]; then echo "no *.test.html found in $here" >&2; exit 1; fi

for page in "${pages[@]}"; do
  echo
  echo "=== $(basename "$page") ==="

  profile="$(mktemp -d)"
  # --allow-file-access-from-files lets the page fetch() the deploy bundle off disk.
  # --host-resolver-rules keeps the run hermetic: no calls to Supabase or the QR service.
  dom="$("$browser" --headless=new --disable-gpu --no-sandbox --no-first-run \
    --allow-file-access-from-files --host-resolver-rules="MAP * ~NOTFOUND" \
    --user-data-dir="$profile" --virtual-time-budget=10000 --dump-dom "file://$page" 2>/dev/null)"
  rm -rf "$profile"

  if [ -z "$dom" ]; then echo 'Browser produced no output.'; failed=$((failed + 1)); continue; fi

  # Strip tags so PASS/FAIL lines read cleanly in the terminal.
  printf '%s' "$dom" | awk '/<pre id="out">/{on=1} on{print} /<\/pre>/{if(on)exit}' |
    sed 's/.*<pre id="out">//; s|</pre>.*||' |
    sed 's/<[^>]*>//g' | sed 's/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#39;/'"'"'/g; s/&amp;/\&/g'

  result="$(printf '%s' "$dom" | grep -o 'RESULT: \(PASS\|FAIL\)[^<]*' | head -1)"
  if [ -n "$result" ]; then
    echo "$result"
    case "$result" in RESULT:\ PASS*) ;; *) failed=$((failed + 1)) ;; esac
  else
    echo 'Could not find a test result in the page output.'
    failed=$((failed + 1))
  fi
done

echo
if [ "$failed" -ne 0 ]; then echo "$failed test file(s) FAILED"; exit 1; fi
echo 'All test files passed.'
