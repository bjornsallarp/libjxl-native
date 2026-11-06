#!/usr/bin/env bash
# Smoke-tests artifacts/package/MightyLittleJxl.Native.*.nupkg the way a consumer uses it:
# a fresh copy of the harness restores the package from that folder only, and runs
# encode/decode with .NET resolving runtimes/<rid>/native/ itself.
# Linux RIDs run in Docker, macOS RIDs on this Mac; Windows: smoke.ps1.
# Usage: ./smoke.sh [all | <rid>...]
set -euo pipefail
cd "$(dirname "$0")"
root=$(pwd)
set -a; source versions.env; set +a
source scripts/run-harness.sh

all_rids=(linux-x64 linux-arm64 linux-musl-x64 linux-musl-arm64 osx-arm64 osx-x64)
if [[ $# -eq 0 || $1 == all ]]; then rids=("${all_rids[@]}"); else rids=("$@"); fi

nupkg=$(ls artifacts/package/MightyLittleJxl.Native.*.nupkg)
version=$(basename "$nupkg" .nupkg); version=${version#MightyLittleJxl.Native.}

smoke=build/smoke
rm -rf "$smoke"
mkdir -p "$smoke/src"
cp tests/Harness/*.cs tests/Harness/Harness.csproj "$smoke/src/"
dotnet build "$smoke/src" -c Release -o "$smoke/app" --nologo -v quiet \
  -p:NativePackageVersion="$version" -p:RestoreSources="$root/artifacts/package" \
  -p:RestorePackagesPath="$root/$smoke/packages" >/dev/null

failed=()
for rid in "${rids[@]}"; do
  echo "==> $rid ($(basename "$nupkg"))"
  if out=$(run_harness "$rid" "$root/$smoke/app" "" "" 2>&1); then
    echo "$out"
    # On Linux the harness prints the file it loaded; it must be this RID's.
    if [[ $rid == linux-* ]] && ! grep -q "^library: .*/runtimes/$rid/native/libjxl_native.so$" <<< "$out"; then
      echo "loaded the wrong library for $rid" >&2; failed+=("$rid")
    fi
  else
    echo "$out"; failed+=("$rid")
  fi
done

if [[ ${#failed[@]} -gt 0 ]]; then echo "package smoke test FAILED: ${failed[*]}" >&2; exit 1; fi
echo "package OK on: ${rids[*]}"
