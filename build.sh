#!/usr/bin/env bash
# Builds libjxl_native into artifacts/native/<rid>/.
# Usage: ./build.sh [all | <rid>...]
# Linux and Windows RIDs build in Docker; macOS RIDs build on this Mac.
set -euo pipefail
cd "$(dirname "$0")"
root=$(pwd)
set -a; source versions.env; set +a

all_rids=(linux-x64 linux-arm64 linux-musl-x64 linux-musl-arm64 osx-arm64 osx-x64 win-x64 win-arm64)
if [[ $# -eq 0 || $1 == all ]]; then rids=("${all_rids[@]}"); else rids=("$@"); fi

src=build/src/libjxl

fetch_source() {
  if [[ ! -d $src ]]; then
    git clone --quiet --depth 1 --branch "$LIBJXL_TAG" https://github.com/libjxl/libjxl.git "$src"
    git -C "$src" submodule update --quiet --init --depth 1 third_party/brotli third_party/highway third_party/skcms
  fi
  local head
  head=$(git -C "$src" rev-parse HEAD)
  if [[ $head != "$LIBJXL_COMMIT" ]]; then
    echo "$src is at $head, expected $LIBJXL_TAG ($LIBJXL_COMMIT); delete it to re-fetch" >&2
    exit 1
  fi
}

# Runs build-native.sh in <image> for <platform>, with the repo mounted at /repo.
in_docker() {
  local rid=$1 image=$2 platform=$3
  docker run --rm --platform "$platform" --env-file versions.env \
    -v "$root:/repo" -w /repo "$image" \
    bash scripts/build-native.sh "$rid" "/repo/$src" "/repo/build/$rid" "/repo/artifacts/native/$rid"
}

musl_image() {
  local platform=$1 tag="libjxl-native-musl:${1#linux/}"
  docker build --quiet --platform "$platform" --build-arg "BASE=$ALPINE_IMAGE" \
    -t "$tag" -f docker/musl.Dockerfile docker >/dev/null
  echo "$tag"
}

fetch_source
for rid in "${rids[@]}"; do
  echo "==> $rid"
  case $rid in
    linux-x64) in_docker "$rid" "$MANYLINUX_X64_IMAGE" linux/amd64 ;;
    linux-arm64) in_docker "$rid" "$MANYLINUX_ARM64_IMAGE" linux/arm64 ;;
    linux-musl-x64) in_docker "$rid" "$(musl_image linux/amd64)" linux/amd64 ;;
    linux-musl-arm64) in_docker "$rid" "$(musl_image linux/arm64)" linux/arm64 ;;
    # Cross-compiled, so the container runs at the host's native architecture.
    win-x64 | win-arm64)
      docker run --rm --env-file versions.env -v "$root:/repo" -w /repo "$LLVM_MINGW_IMAGE" \
        bash scripts/build-native.sh "$rid" "/repo/$src" "/repo/build/$rid" "/repo/artifacts/native/$rid" ;;
    osx-arm64 | osx-x64) scripts/build-native.sh "$rid" "$root/$src" "$root/build/$rid" "$root/artifacts/native/$rid" ;;
    *) echo "unknown or not yet supported rid: $rid" >&2; exit 1 ;;
  esac
done
