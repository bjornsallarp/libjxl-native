#!/usr/bin/env bash
# Packs artifacts/native/<rid>/ into artifacts/package/LibJxl.Native.<version>.nupkg.
# Every RID present must have a passing test result; smoke-test the package with
# smoke.sh / smoke.ps1 afterwards.
# Usage: ./pack.sh [extra dotnet pack arguments]
set -euo pipefail
cd "$(dirname "$0")"

required=(linux-x64 linux-musl-x64 osx-arm64 win-x64)

# build-native.sh clears test-result.txt, so a pass always belongs to the current build.
rids=()
for dir in artifacts/native/*/; do
  rid=$(basename "$dir")
  if [[ $(tail -n 1 "$dir/test-result.txt" 2>/dev/null | tr -d '\r') != OK ]]; then
    echo "$rid has no passing test-result.txt; run ./test.sh $rid (or test.ps1 on Windows)" >&2
    exit 1
  fi
  rids+=("$rid")
done
for rid in "${required[@]}"; do
  [[ -d artifacts/native/$rid ]] || { echo "required RID missing: $rid" >&2; exit 1; }
done
echo "packing: ${rids[*]}"

rm -rf artifacts/package
dotnet pack src/LibJxl.Native -o artifacts/package --nologo -v quiet "$@"
ls artifacts/package/LibJxl.Native.*.nupkg
