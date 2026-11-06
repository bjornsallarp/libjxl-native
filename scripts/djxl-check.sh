#!/usr/bin/env bash
# Decodes every <name>.jxl under <dir> with libjxl's own djxl and checks the
# pixels equal <name>.raw, as written by `Harness.dll --dump <dir>`.
# Usage: scripts/djxl-check.sh <dir> [djxl]
set -euo pipefail

dir=$1 djxl=${2:-djxl}
"$djxl" --version | head -1

failed=0 count=0
while IFS= read -r jxl; do
  base=${jxl%.jxl}
  # Raw pixels carry 3 or 4 channels; PAM is needed to keep alpha.
  ext=ppm; [[ $(basename "$base") == rgba-* ]] && ext=pam
  out=$(mktemp).$ext
  size=$(wc -c < "$base.raw" | tr -d ' ')
  if "$djxl" "$jxl" "$out" >/dev/null 2>&1 && cmp -s <(tail -c "$size" "$out") "$base.raw"; then
    echo "same      $jxl"
  else
    echo "DIFFERENT $jxl"; failed=$((failed + 1))
  fi
  rm -f "$out"; count=$((count + 1))
done < <(find "$dir" -name '*.jxl' | sort)

[[ $count -gt 0 ]] || { echo "no .jxl files under $dir" >&2; exit 1; }
[[ $failed -eq 0 ]] || { echo "$failed of $count differ" >&2; exit 1; }
echo "all $count decode to the source pixels"
