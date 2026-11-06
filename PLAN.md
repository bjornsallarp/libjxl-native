# MightyLittleJxl.Native: plan

## Why

There is no official cross-platform NuGet package with native libjxl (the JPEG XL reference library) binaries. This repo builds libjxl from source and ships it as one standalone `.nupkg` for any .NET project that wants to P/Invoke libjxl on every common platform, with nothing installed on the machine. It assumes no particular consumer or use case. The package is published to nuget.org.

## What to build

One NuGet package, `MightyLittleJxl.Native`, containing **only native binaries**: no managed assembly, no `lib/` folder. The consumer writes its own P/Invoke against libjxl's C API, so the package version must pin the exact libjxl version the binaries were built from.

**Native libjxl for 8 runtime identifiers**, under `runtimes/<rid>/native/`:

| RID | Notes |
|---|---|
| `linux-x64` | glibc; **required** |
| `linux-musl-x64` | Alpine, e.g. `aspnet:10.0-alpine`; **required** |
| `osx-arm64` | Apple silicon; **required** |
| `win-x64` | **required** |
| `linux-arm64`, `linux-musl-arm64` | nice to have |
| `osx-x64` | Intel Macs; nice to have |
| `win-arm64` | nice to have |

A test-only harness in this repo (not packed) holds the minimal P/Invoke needed to exercise the binaries; see [Tests](#tests).

**Everything is automated on GitHub Actions** (free for this public repo): every RID is built and tested on a runner of its own platform, the package is packed and smoke-tested everywhere, new libjxl releases open a bump PR, and merging to main releases. See [CI](#ci-github-actions). The same scripts run locally on an Apple silicon Mac (Linux and Windows builds in Docker, macOS natively) for debugging.

### Local prerequisites (optional, Mac)

- Docker Desktop or OrbStack, with Rosetta for amd64 emulation enabled.
- Rosetta 2 (`softwareupdate --install-rosetta`).
- Xcode Command Line Tools, plus `cmake`, `ninja` and `git` (Homebrew).
- .NET 10 SDK. `test.sh`/`smoke.sh` run `osx-x64` under Rosetta with an x64 .NET runtime, installed into `build/dotnet-x64` unless an x64 SDK is installed side by side.
- Windows can't be tested locally; CI does it.

## Native build requirements

- **libjxl version:** pin the latest stable tag, currently `v0.12.0` (2026-07-01), in `versions.env` (`LIBJXL_TAG` + `LIBJXL_COMMIT`). The package version follows it (`0.12.0`). A repack of the same libjxl adds `PACKAGE_VERSION=0.12.0.1` (a fourth part) to `versions.env`.
- **One self-contained shared library per RID.**
  - Link libjxl, libjxl_cms and libjxl_threads and their dependencies (highway, brotli, skcms; no lcms2 needed) statically into a single library.
  - The only allowed runtime dependencies are the OS's own: libc/libm/libpthread, and libc++ on macOS. On Linux, link libstdc++ and libgcc statically. On Windows, llvm-mingw with `-static`, leaving only system DLLs (KERNEL32 and the UCRT, which ships with Windows 10+).
  - Verify with `ldd` / `otool -L` / `llvm-readobj --coff-imports` as part of the build.
- **Give the library a unique name** so a system libjxl (Homebrew, apt, apk) can never be picked up instead: `libjxl_native.so`, `libjxl_native.dylib`, `jxl_native.dll`. Consumers P/Invoke `"jxl_native"`. Export the full public `Jxl*` C API of all three libraries (the consumer decides what to bind, e.g. `JxlThreadParallelRunner*` for multithreaded encodes) and nothing else. That is 115 functions for v0.12.0, the same set upstream's own `jxl.dll` + `jxl_cms.dll` + `jxl_threads.dll` export. `gain_map.h` and `compressed_icc.h` are declared publicly but implemented in libjxl's extras library, which upstream doesn't ship as a shared library either, so they are not exported. The build checks the exported set against the headers.
- **Portability baselines:**
  - glibc: built on manylinux_2_28 (AlmaLinux 8, GCC 14). **glibc floor: 2.27** (highest versioned symbol required, x64 and arm64).
  - musl: build on Alpine 3.20 or newer, matching the .NET Alpine images.
  - macOS: built with the Xcode command line tools, deployment target 13.0. CI builds each arch natively (`macos-15`, `macos-15-intel`); on an Apple silicon Mac `osx-x64` is cross-compiled with `-arch x86_64`.
  - Windows: x64 and arm64 cross-compiled with llvm-mingw (clang, UCRT) in a Linux Docker container, at the host's native architecture. Runtime dependencies are KERNEL32 and the UCRT's `api-ms-win-crt-*` API sets, so Windows 10 or later (as .NET 10 requires anyway).
- **Build hosts:** Linux and Windows builds run in Docker, in each target's own pinned image. In CI every Linux build runs on a runner of its own architecture; on a Mac, x64 images run under emulation (`--platform linux/amd64`).
- **Reproducible:** one `build.sh <rid>|all` that runs the right Docker image or, for macOS, the host toolchain, and writes `artifacts/native/<rid>/`. Pin the base images by digest and the libjxl tag; clone submodules for the vendored deps.

## Packaging

- `src/MightyLittleJxl.Native/MightyLittleJxl.Native.csproj` is a packaging-only SDK-style project (`IncludeBuildOutput=false`, `SuppressDependenciesWhenPacking=true`, `NoWarn=NU5128`), packed with `dotnet pack`. It packs every `artifacts/native/<rid>/` library present to `runtimes/<rid>/native/<file>`. The package has no `lib/` folder and no dependencies, and installs into any target framework.
- The version is read from `versions.env`: `PACKAGE_VERSION` if set, otherwise `LIBJXL_TAG` without the `v`.
- Alpine gets the musl file: the package smoke test confirms .NET loads `runtimes/linux-musl-<arch>/native/` there, not the glibc one.
- `THIRD-PARTY-NOTICES.md` (repo root, also packed) has the full licence texts: libjxl BSD-3-Clause plus its patent grant, Brotli MIT, Highway under BSD-3-Clause (it is dual-licensed), skcms BSD-3-Clause, and for the Windows DLLs the LLVM runtime (Apache-2.0 WITH LLVM-exception), MinGW-w64 runtime and winpthreads.
- Package metadata: id `MightyLittleJxl.Native`, license expression `BSD-3-Clause AND MIT`, description naming the libjxl version and RIDs, `src/MightyLittleJxl.Native/README.md` as the package readme, tags, project and repository URLs (`dotnet pack` records the commit).

## Tests

**Every RID that ships is tested on that RID; nothing is packed untested.** The test-only harness is a small `net10.0` console with the P/Invoke it needs. For each RID it:

- Loads the freshly built library.
- Encodes and decodes four 2048×2048 test images and asserts the round trip is bit-exact: photo-like RGB (gradients with photographic noise, flat blocks, hard-edged checkerboards), pure noise, flat palette art, and photo-like RGBA with opaque, transparent and graded alpha. They are generated deterministically in `tests/Harness/TestImages.cs` rather than committed: raw files would be 12–16 MB each, and PNGs would need an image library.
- Reports the median of 10 effort-1 encodes of the photo-like image, for the performance criterion.
The dependency check runs in `build-native.sh`; loading the library in a clean runtime image proves those dependencies resolve.

Where each RID runs:

| RID | Test host |
|---|---|
| RID | CI runner | Test host |
|---|---|---|
| `linux-x64`, `linux-musl-x64` | `ubuntu-24.04` | `mcr.microsoft.com/dotnet/runtime:10.0` / `:10.0-alpine` in Docker |
| `linux-arm64`, `linux-musl-arm64` | `ubuntu-24.04-arm` | same images, arm64 |
| `osx-arm64` | `macos-15` | the runner |
| `osx-x64` | `macos-15-intel` | the runner (locally: Rosetta) |
| `win-x64` | `windows-2025` | the runner (`test.ps1`) |
| `win-arm64` | `windows-11-arm` | the runner (`test.ps1`) |

`test.sh <rid>|all` (Linux, macOS) and `test.ps1 -Rid <rid>` (Windows) run the harness and dump each encoded `.jxl` with its source pixels to `build/dump/<rid>/`; `scripts/djxl-check.sh` decodes those with `djxl`. CI runs that check on all eight RIDs' dumps with Ubuntu's `djxl` (libjxl-tools), a different libjxl version.

**djxl cross-check (2026-11-06):** the 32 `.jxl` files encoded on all eight RIDs decode with Homebrew's `djxl` v0.12.0 to exactly the source pixels (`scripts/djxl-check.sh`; Windows files from the workflow's `windows-dump-<rid>` artifacts, run 42233817821). The encoded bytes are identical across RIDs, Windows included, except `osx-x64` under Rosetta, which picks a different SIMD target and so makes slightly different (still lossless) encoder choices. Running x64 binaries under emulation proves they load and round-trip correctly, but performance is only measured natively on `osx-arm64`.

## Pack and smoke test

- `pack.sh` takes every `artifacts/native/<rid>/`, refuses to pack if any lacks a passing `test-result.txt` (a rebuild clears it) or a required RID is missing, and runs `dotnet pack` into `artifacts/package/`.
- `smoke.sh <rid>...` (Linux, macOS) and `smoke.ps1 -Rid <rid>` (Windows) smoke-test the `.nupkg` the way a consumer uses it: a fresh copy of the harness restores it from that folder only (own package cache, no other sources) and runs encode → decode without `JXL_NATIVE_PATH`, so .NET resolves `runtimes/<rid>/native/` itself. On Linux the harness prints the loaded file and `smoke.sh` checks it is that RID's (musl on Alpine).

## CI (GitHub Actions)

Actions are pinned by commit SHA. All runners are GitHub-hosted and free for public repos.

**`ci.yml`** runs on every push to main, every pull request, and on dispatch:

1. `native` (6 jobs): build and test each Linux and macOS RID on its own runner (`build.sh`, `test.sh`).
2. `windows-build` cross-compiles both Windows DLLs on `ubuntu-24.04`; `windows-test` tests each on `windows-2025` / `windows-11-arm` (`test.ps1`).
3. `djxl`: every RID's encoded files must decode with Ubuntu's `djxl` to exactly the source pixels.
4. `package`: gathers all eight tested libraries and runs `pack.sh`.
5. `smoke` (8 jobs): smoke-tests the final `.nupkg` on every RID's runner.
6. `release`, on main only: if no GitHub release `v<version>` exists yet, push the `.nupkg` to nuget.org (`dotnet nuget push --skip-duplicate`), then create the release with the `.nupkg` attached. It authenticates with nuget.org Trusted Publishing: the job runs in the `nuget` environment (deployable from `main` only), and `NuGet/login` exchanges its OIDC token for a short-lived API key; the nuget.org policy for `MightyLittleJxl.*` accepts only `bjornsallarp/libjxl-native`, `ci.yml`, environment `nuget`. No secret is stored. So merging a new version to main publishes it, and other merges publish nothing.

**`update.yml`** runs weekly (Monday 06:00 UTC) and on dispatch. If libjxl's latest release differs from `LIBJXL_TAG`, it commits a bump (tag, commit, README version, drops `PACKAGE_VERSION`) to `bump/libjxl-<tag>`, opens a PR, and dispatches `ci.yml` on that branch, since pushes and PRs made with `GITHUB_TOKEN` trigger no workflows. Its checks show on the PR; merging releases. It needs the repo setting "Allow GitHub Actions to create and approve pull requests".

## Harness settings

The harness, and the performance criterion below, use:

- Encode: interleaved 8-bit sRGB, 3 or 4 channels. `JxlEncoderSetFrameLossless`, `uses_original_profile = true`, sRGB colour encoding, `JXL_ENC_FRAME_SETTING_EFFORT = 1`, no parallel runner.
- Decode: 8-bit interleaved output.

## Consumer documentation

The package readme (`src/MightyLittleJxl.Native/README.md`, consumers only) and the repo `README.md` tell consumers:

- The library name to P/Invoke (`"jxl_native"`) and which RIDs are included.
- That the exported API is exactly libjxl's public C API at the pinned tag, with a link to that tag's headers. Struct layouts and enums can change between libjxl versions, so a binding must match the package version.
- A minimal `[LibraryImport]` example (e.g. `JxlEncoderVersion`) and a pointer to the harness as a fuller encode/decode example.

## Acceptance criteria

- [x] The `.nupkg` contains a native library for at least the four required RIDs, each self-contained per the dependency check. (All eight.)
- [x] The `.nupkg` contains no managed assembly.
- [x] On every packed RID, on that RID's test host, the harness's encode then decode of the test images is bit-exact. libjxl's `djxl` (any version) decodes the output to the same pixels; check that once by hand.
- [x] All native libraries are built in Docker, except macOS, which is built with the host toolchain.
- [x] Lossless effort-1 encode of a 2048×2048 RGB image takes ≤ 20 ms single-threaded on an M-series Mac, close to `cjxl -d 0 -e 1 --num_threads=0`. This confirms an optimised build (release flags, highway SIMD dispatch) rather than serving any one use case. (Median 10.8 ms; `cjxl` v0.12.0 takes 13.1 ms on the same image, output within 2 bytes.)
- [x] A fresh `dotnet new console` with only this `.nupkg` in a local folder source restores, builds and runs encode → decode on macOS, Windows, glibc Linux and Alpine, with nothing installed on the machine. (A copy of the harness stands in for the console app: `smoke.sh` / `smoke.ps1`.)
- [x] `README.md` covers the consumer documentation above, and how CI builds, tests and releases, how to run it locally, and how bumps and repacks work.
- [ ] `ci.yml` passes on main for all eight RIDs and publishes `v0.12.0` to nuget.org and as a GitHub release.
- [ ] `update.yml` opens a bump PR with a passing CI run when libjxl releases a new version (can be exercised by dispatching it against an older pin).

## Out of scope

A managed binding; consumers write their own.
