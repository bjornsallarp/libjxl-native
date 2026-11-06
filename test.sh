#!/usr/bin/env bash
# Runs the encode/decode harness against artifacts/native/<rid>/ on that RID:
# Linux in Docker (.NET runtime images), macOS on this Mac.
# Usage: ./test.sh [all | <rid>...]
# A pass writes artifacts/native/<rid>/test-result.txt.
set -euo pipefail
cd "$(dirname "$0")"
root=$(pwd)
set -a; source versions.env; set +a

all_rids=(linux-x64 linux-arm64 linux-musl-x64 linux-musl-arm64 osx-arm64 osx-x64)
if [[ $# -eq 0 || $1 == all ]]; then rids=("${all_rids[@]}"); else rids=("$@"); fi

# The harness is portable IL, so one build serves every RID.
dotnet build tests/Harness -c Release -o build/harness --nologo -v quiet >/dev/null

in_docker() {
  local rid=$1 image=$2 platform=$3
  docker run --rm --platform "$platform" \
    -v "$root/build/harness:/harness:ro" -v "$root/artifacts/native/$rid:/native:ro" \
    -e JXL_NATIVE_PATH=/native/libjxl_native.so "$image" dotnet /harness/Harness.dll
}

on_host() {
  local dotnet=$1 rid=$2
  JXL_NATIVE_PATH="$root/artifacts/native/$rid/libjxl_native.dylib" "$dotnet" build/harness/Harness.dll
}

failed=()
for rid in "${rids[@]}"; do
  echo "==> $rid"
  dir=artifacts/native/$rid
  rm -f "$dir/test-result.txt"
  if [[ ! -d $dir ]]; then echo "not built: $dir" >&2; failed+=("$rid"); continue; fi
  log=$(mktemp)
  set +e
  case $rid in
    linux-x64) in_docker "$rid" "$DOTNET_RUNTIME_X64_IMAGE" linux/amd64 ;;
    linux-arm64) in_docker "$rid" "$DOTNET_RUNTIME_ARM64_IMAGE" linux/arm64 ;;
    linux-musl-x64) in_docker "$rid" "$DOTNET_RUNTIME_ALPINE_X64_IMAGE" linux/amd64 ;;
    linux-musl-arm64) in_docker "$rid" "$DOTNET_RUNTIME_ALPINE_ARM64_IMAGE" linux/arm64 ;;
    osx-arm64) on_host dotnet "$rid" ;;
    osx-x64)
      # Runs under Rosetta with an x64 .NET runtime, installed into build/ unless already side by side.
      x64=/usr/local/share/dotnet/x64/dotnet
      if [[ ! -x $x64 ]]; then
        x64=$root/build/dotnet-x64/dotnet
        if [[ ! -x $x64 ]]; then
          curl -sSL https://dot.net/v1/dotnet-install.sh -o build/dotnet-install.sh
          bash build/dotnet-install.sh --runtime dotnet --channel 10.0 --architecture x64 \
            --install-dir build/dotnet-x64 --no-path >/dev/null
        fi
      fi
      on_host "$x64" "$rid" ;;
    *) echo "unknown rid: $rid" >&2; false ;;
  esac 2>&1 | tee "$log"
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
