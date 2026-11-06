#!/usr/bin/env bash
# Runs the encode/decode harness against artifacts/native/<rid>/ on that RID:
# Linux in Docker (.NET runtime images), macOS on this Mac. Windows: test.ps1.
# Usage: ./test.sh [all | <rid>...]
# A pass writes artifacts/native/<rid>/test-result.txt; each run also dumps the
# encoded files to build/dump/<rid>/ for scripts/djxl-check.sh.
set -euo pipefail
cd "$(dirname "$0")"
root=$(pwd)
set -a; source versions.env; set +a
source scripts/run-harness.sh

all_rids=(linux-x64 linux-arm64 linux-musl-x64 linux-musl-arm64 osx-arm64 osx-x64)
if [[ $# -eq 0 || $1 == all ]]; then rids=("${all_rids[@]}"); else rids=("$@"); fi

# The harness is portable IL, so one build serves every RID.
dotnet build tests/Harness -c Release -o build/harness --nologo -v quiet >/dev/null

failed=()
for rid in "${rids[@]}"; do
  echo "==> $rid"
  dir=artifacts/native/$rid
  rm -f "$dir/test-result.txt"
  lib=$(ls "$dir"/libjxl_native.* 2>/dev/null | head -1 || true)
  if [[ -z $lib ]]; then echo "not built: $dir" >&2; failed+=("$rid"); continue; fi
  rm -rf "build/dump/$rid"
  log=$(mktemp)
  set +e
  run_harness "$rid" "$root/build/harness" "$root/$lib" "$root/build/dump/$rid" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  set -e
  if [[ $status -eq 0 ]]; then
    { echo "commit: $(git rev-parse HEAD 2>/dev/null || echo none)"; echo "date: $(date -u +%FT%TZ)"; cat "$log"; } > "$dir/test-result.txt"
  else
    failed+=("$rid")
  fi
  rm -f "$log"
done

if [[ ${#failed[@]} -gt 0 ]]; then echo "FAILED: ${failed[*]}" >&2; exit 1; fi
echo "all passed: ${rids[*]}"
