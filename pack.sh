#!/usr/bin/env bash
# Packs artifacts/native/<rid>/ into artifacts/package/LibJxl.Native.<version>.nupkg,
# then smoke-tests the package: a copy of the harness restores it from a local
# folder and runs encode/decode on Linux (glibc and musl, in Docker) and macOS,
# with .NET picking runtimes/<rid>/native/ itself. The windows workflow covers Windows.
# Usage: ./pack.sh [-p:PackageVersion=0.12.0.1]
set -euo pipefail
cd "$(dirname "$0")"
root=$(pwd)
set -a; source versions.env; set +a

required=(linux-x64 linux-musl-x64 osx-arm64 win-x64)

# Every RID that ships must have passed its encode/decode test since it was built
# (build-native.sh clears test-result.txt; Windows results come from fetch-windows.sh).
rids=()
for dir in artifacts/native/*/; do
  rid=$(basename "$dir")
  if [[ $(tail -n 1 "$dir/test-result.txt" 2>/dev/null | tr -d '\r') != OK ]]; then
    echo "$rid has no passing test-result.txt; run ./test.sh $rid (or ./fetch-windows.sh)" >&2
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
nupkg=$(ls artifacts/package/LibJxl.Native.*.nupkg)
version=$(basename "$nupkg" .nupkg); version=${version#LibJxl.Native.}
echo "packed: $nupkg"

# A fresh copy of the harness, restored only from the local package folder into
# its own package cache, so nothing stale or local leaks in.
smoke=build/smoke
rm -rf "$smoke"
mkdir -p "$smoke/src"
cp tests/Harness/*.cs tests/Harness/Harness.csproj "$smoke/src/"
dotnet build "$smoke/src" -c Release -o "$smoke/app" --nologo -v quiet \
  -p:LibJxlNativeVersion="$version" -p:RestoreSources="$root/artifacts/package" \
  -p:RestorePackagesPath="$root/$smoke/packages" >/dev/null

failed=()
smoke_run() {
  local rid=$1; shift
  echo "==> $rid (package)"
  local out
  if out=$("$@" 2>&1); then
    echo "$out"
    # On Linux the harness prints the file it loaded; it must be this RID's.
    if [[ $rid == linux-* ]] && ! grep -q "^library: .*/runtimes/$rid/native/libjxl_native.so$" <<< "$out"; then
      echo "loaded the wrong library for $rid" >&2; failed+=("$rid")
    fi
  else
    echo "$out"; failed+=("$rid")
  fi
}
in_docker() {
  docker run --rm --platform "$2" -v "$root/$smoke/app:/app:ro" "$1" dotnet /app/Harness.dll
}

smoke_run linux-x64 in_docker "$DOTNET_RUNTIME_X64_IMAGE" linux/amd64
smoke_run linux-arm64 in_docker "$DOTNET_RUNTIME_ARM64_IMAGE" linux/arm64
smoke_run linux-musl-x64 in_docker "$DOTNET_RUNTIME_ALPINE_X64_IMAGE" linux/amd64
smoke_run linux-musl-arm64 in_docker "$DOTNET_RUNTIME_ALPINE_ARM64_IMAGE" linux/arm64
smoke_run osx-arm64 dotnet "$smoke/app/Harness.dll"
x64=/usr/local/share/dotnet/x64/dotnet; [[ -x $x64 ]] || x64=build/dotnet-x64/dotnet
if [[ -x $x64 ]]; then smoke_run osx-x64 "$x64" "$smoke/app/Harness.dll"; else echo "skipping osx-x64: run ./test.sh osx-x64 once to install x64 .NET"; fi

if [[ ${#failed[@]} -gt 0 ]]; then echo "package smoke test FAILED: ${failed[*]}" >&2; exit 1; fi
echo "package OK: $nupkg"
