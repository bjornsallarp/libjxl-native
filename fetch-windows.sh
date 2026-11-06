#!/usr/bin/env bash
# Downloads the Windows DLLs that passed the windows workflow into
# artifacts/native/win-*/, replacing any local Windows build.
# Usage: ./fetch-windows.sh [run-id]   (default: latest successful run)
set -euo pipefail
cd "$(dirname "$0")"

run=${1:-$(gh run list --workflow windows.yml --status success --limit 1 --json databaseId --jq '.[0].databaseId')}
[[ -n $run ]] || { echo "no successful windows workflow run found" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
gh run download "$run" --pattern 'windows-tested-*' --dir "$tmp"
for rid in win-x64 win-arm64; do
  [[ -f $tmp/windows-tested-$rid/test-result.txt ]] || { echo "run $run has no passing $rid" >&2; exit 1; }
  rm -rf "artifacts/native/$rid"
  mkdir -p artifacts/native
  mv "$tmp/windows-tested-$rid" "artifacts/native/$rid"
  echo "$rid: $(grep -m1 '^commit:' "artifacts/native/$rid/test-result.txt") (run $run)"
done
