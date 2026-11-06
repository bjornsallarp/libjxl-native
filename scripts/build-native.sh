#!/usr/bin/env bash
# Builds libjxl, libjxl_cms and libjxl_threads as static libraries and links
# them, with highway, brotli and skcms, into one shared library per RID.
# Runs inside the Linux build containers, the llvm-mingw container (Windows)
# and on the macOS host.
# Usage: build-native.sh <rid> <libjxl-src> <work-dir> <out-dir>
set -euo pipefail

rid=$1 src=$2 work=$3 out=$4
here=$(cd "$(dirname "$0")" && pwd)
jobs=$(getconf _NPROCESSORS_ONLN)

case $rid in
  osx-*) os=osx ;;
  linux-*) os=linux ;;
  win-*) os=win ;;
  *) echo "unsupported rid: $rid" >&2; exit 1 ;;
esac

# A static build compiles the public API as hidden. Undefining *_STATIC_DEFINE
# and predefining the export macros keeps exactly the public API visible.
undef="-UJXL_STATIC_DEFINE -UJXL_CMS_STATIC_DEFINE -UJXL_THREADS_STATIC_DEFINE -include $here/visibility.h"

cmake_args=(
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
  -DBUILD_TESTING=OFF
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  "-DCMAKE_C_FLAGS=$undef"
  "-DCMAKE_CXX_FLAGS=$undef"
  -DJPEGXL_ENABLE_TOOLS=OFF
  -DJPEGXL_ENABLE_JPEGLI=OFF
  -DJPEGXL_ENABLE_BENCHMARK=OFF
  -DJPEGXL_ENABLE_EXAMPLES=OFF
  -DJPEGXL_ENABLE_MANPAGES=OFF
  -DJPEGXL_ENABLE_DOXYGEN=OFF
  -DJPEGXL_ENABLE_JNI=OFF
  -DJPEGXL_ENABLE_SJPEG=OFF
  -DJPEGXL_ENABLE_OPENEXR=OFF
  -DJPEGXL_ENABLE_SKCMS=ON
  -DJPEGXL_ENABLE_TCMALLOC=OFF
  -DJPEGXL_BUNDLE_LIBPNG=OFF
  -DJPEGXL_FORCE_SYSTEM_BROTLI=OFF
  -DJPEGXL_FORCE_SYSTEM_HWY=OFF
)
if command -v ninja >/dev/null; then cmake_args+=(-G Ninja); fi

if [[ $os == osx ]]; then
  arch=${rid#osx-}; [[ $arch == x64 ]] && arch=x86_64
  cmake_args+=(-DCMAKE_OSX_ARCHITECTURES=$arch "-DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_DEPLOYMENT_TARGET")
elif [[ $os == win ]]; then
  case $rid in
    win-x64) triple=x86_64-w64-mingw32 proc=AMD64 ;;
    win-arm64) triple=aarch64-w64-mingw32 proc=ARM64 ;;
    *) echo "unsupported rid: $rid" >&2; exit 1 ;;
  esac
  cmake_args+=(
    -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=$proc
    -DCMAKE_C_COMPILER=$triple-clang -DCMAKE_CXX_COMPILER=$triple-clang++
    -DCMAKE_RC_COMPILER=$triple-windres
  )
fi

cmake -S "$src" -B "$work" "${cmake_args[@]}"
cmake --build "$work" --target jxl jxl_cms jxl_threads -j "$jobs"

lib() {
  local f
  f=$(find "$work" -name "$1" -type f | head -1)
  [[ -n $f ]] || { echo "missing $1" >&2; exit 1; }
  echo "$f"
}
jxl=$(lib libjxl.a) cms=$(lib libjxl_cms.a) threads=$(lib libjxl_threads.a)
deps=("$(lib libhwy.a)" "$(lib 'libbrotlienc*.a')" "$(lib 'libbrotlidec*.a')" "$(lib 'libbrotlicommon*.a')")

mkdir -p "$out"
rm -f "$out"/*

if [[ $os == linux ]]; then
  so="$out/libjxl_native.so"
  c++ -shared -o "$so" -Wl,-soname,libjxl_native.so \
    -Wl,--whole-archive "$jxl" "$cms" "$threads" -Wl,--no-whole-archive "${deps[@]}" \
    -Wl,--version-script="$here/exports.map" -Wl,-z,defs -Wl,--as-needed -Wl,-O1 \
    -static-libstdc++ -static-libgcc -lm -lpthread
  strip --strip-unneeded "$so"
  exported=$(nm -D --defined-only "$so" | awk '{print $3}' | sort)
  needed=$(readelf -d "$so" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | sort)
  allowed='^(libc\.so\.6|libm\.so\.6|libpthread\.so\.0|libdl\.so\.2|ld-linux-.*\.so\.[0-9]+|libc\.musl-[a-z0-9_]+\.so\.1)$'
  glibc_floor=
  if [[ $rid != linux-musl-* ]]; then
    glibc_floor=$(objdump -T "$so" | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1)
  fi
elif [[ $os == win ]]; then
  # -static links libc++, libunwind and winpthreads in, leaving only system DLLs.
  so="$out/jxl_native.dll"
  $triple-clang++ -shared -o "$so" \
    -Wl,--whole-archive "$jxl" "$cms" "$threads" -Wl,--no-whole-archive "${deps[@]}" \
    -static -s
  exported=$(llvm-readobj --coff-exports "$so" | sed -n 's/^ *Name: //p' | sort)
  needed=$(llvm-readobj --coff-imports "$so" | sed -n 's/^ *Name: //p' | sort -u)
  allowed='^(KERNEL32\.dll|api-ms-win-crt-[a-z0-9-]+\.dll)$'
  glibc_floor=
else
  so="$out/libjxl_native.dylib"
  c++ -dynamiclib -arch "$arch" "-mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET" -o "$so" \
    -install_name @rpath/libjxl_native.dylib \
    -Wl,-force_load,"$jxl" -Wl,-force_load,"$cms" -Wl,-force_load,"$threads" "${deps[@]}" \
    -Wl,-exported_symbols_list,"$here/exports.syms" -Wl,-dead_strip
  strip -x "$so"
  exported=$(nm -gU "$so" | awk '{print $3}' | sed 's/^_//' | sort)
  needed=$(otool -L "$so" | tail -n +2 | awk '{print $1}' | grep -v libjxl_native | sort)
  allowed='^(/usr/lib/libc\+\+\.1\.dylib|/usr/lib/libSystem\.B\.dylib)$'
  glibc_floor=
fi

# Every JXL_*EXPORT function in the public headers must be exported, and nothing
# else. gain_map.h and compressed_icc.h are implemented in libjxl's extras
# library, which upstream's shared libjxl doesn't export either.
headers=$(ls "$src"/lib/include/jxl/*.h | grep -Ev '/(gain_map|compressed_icc)\.h$')
expected=$(echo "$headers" | xargs perl -0777 -ne 'print "$1\n" while /JXL_(?:CMS_|THREADS_)?EXPORT\b[^;{}]*?\b(Jxl\w+)\s*\(/g' | sort -u)
if ! diff <(echo "$expected") <(echo "$exported") >/dev/null; then
  echo "export mismatch (< expected from headers, > exported):" >&2
  diff <(echo "$expected") <(echo "$exported") >&2 || true
  exit 1
fi
bad=$(echo "$needed" | grep -Ev "$allowed" || true)
if [[ -n $bad ]]; then
  echo "disallowed dependencies:" >&2; echo "$bad" >&2; exit 1
fi

{
  echo "rid: $rid"
  echo "libjxl: $LIBJXL_TAG ($LIBJXL_COMMIT)"
  echo "exports: $(echo "$exported" | wc -l | tr -d ' ') Jxl* functions"
  [[ -n $glibc_floor ]] && echo "glibc floor: $glibc_floor"
  echo "dependencies:"; echo "$needed" | sed 's/^/  /'
} > "$out/build-info.txt"
cat "$out/build-info.txt"
