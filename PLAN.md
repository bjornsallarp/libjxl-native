# LibJxl.Native: plan

## Why

There is no official cross-platform NuGet package with native libjxl (the JPEG XL reference library) binaries. This repo builds libjxl from source and ships it as one standalone `.nupkg` for any .NET project that wants to P/Invoke libjxl on every common platform, with nothing installed on the machine. It assumes no particular consumer or use case. The package is published to a private NuGet feed.

## What to build

One NuGet package, `LibJxl.Native`, containing **only native binaries**: no managed assembly, no `lib/` folder. The consumer writes its own P/Invoke against libjxl's C API, so the package version must pin the exact libjxl version the binaries were built from.

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

Everything is built locally on an Apple silicon Mac: Linux and Windows in Docker, macOS natively. Linux and macOS are also tested locally. Windows is tested on GitHub-hosted runners through one manually triggered workflow; there is no other CI.

### Prerequisites on the Mac

- Docker Desktop or OrbStack, with Rosetta for amd64 emulation enabled.
- Rosetta 2 (`softwareupdate --install-rosetta`).
- Xcode Command Line Tools, plus `cmake`, `ninja` and `git` (Homebrew).
- .NET 10 SDK for arm64. `test.sh` runs `osx-x64` under Rosetta with an x64 .NET runtime, which it installs into `build/dotnet-x64` if no x64 SDK is installed side by side.
- `gh` CLI, logged in, to trigger the Windows workflow and download its results.

## Native build requirements

- **libjxl version:** pin the latest stable tag, currently `v0.12.0` (2026-07-01). The package version follows it (`0.12.0`). A repack of the same libjxl bumps a fourth part or uses a suffix the agent picks and documents here.
- **One self-contained shared library per RID.**
  - Link libjxl, libjxl_cms and libjxl_threads and their dependencies (highway, brotli, skcms; no lcms2 needed) statically into a single library.
  - The only allowed runtime dependencies are the OS's own: libc/libm/libpthread, and libc++ on macOS. On Linux, link libstdc++ and libgcc statically. On Windows, llvm-mingw with `-static`, leaving only system DLLs (KERNEL32 and the UCRT, which ships with Windows 10+).
  - Verify with `ldd` / `otool -L` / `llvm-readobj --coff-imports` as part of the build.
- **Give the library a unique name** so a system libjxl (Homebrew, apt, apk) can never be picked up instead: `libjxl_native.so`, `libjxl_native.dylib`, `jxl_native.dll`. Consumers P/Invoke `"jxl_native"`. Export the full public `Jxl*` C API of all three libraries (the consumer decides what to bind, e.g. `JxlThreadParallelRunner*` for multithreaded encodes) and nothing else. That is 115 functions for v0.12.0, the same set upstream's own `jxl.dll` + `jxl_cms.dll` + `jxl_threads.dll` export. `gain_map.h` and `compressed_icc.h` are declared publicly but implemented in libjxl's extras library, which upstream doesn't ship as a shared library either, so they are not exported. The build checks the exported set against the headers.
- **Portability baselines:**
  - glibc: built on manylinux_2_28 (AlmaLinux 8, GCC 14). **glibc floor: 2.27** (highest versioned symbol required, x64 and arm64).
  - musl: build on Alpine 3.20 or newer, matching the .NET Alpine images.
  - macOS: built natively on the Mac host with the Xcode command line tools, deployment target 13.0. `osx-x64` is cross-compiled with `-arch x86_64`.
  - Windows: x64 and arm64 cross-compiled with llvm-mingw (clang, UCRT) in a Linux Docker container, at the host's native architecture. Runtime dependencies are KERNEL32 and the UCRT's `api-ms-win-crt-*` API sets, so Windows 10 or later (as .NET 10 requires anyway).
- **Build hosts:** Linux and Windows builds run in Docker on the Mac. arm64 images run natively; x64 images run under emulation (`--platform linux/amd64`), which is slower but keeps each build in its target's own image. The Windows workflow runs the same `build.sh` in the same pinned image on a GitHub Linux runner.
- **Reproducible:** one `build.sh <rid>|all` that runs the right Docker image or, for macOS, the host toolchain, and writes `artifacts/native/<rid>/`. Pin the base images by digest and the libjxl tag; clone submodules for the vendored deps.

## Packaging

- A packaging-only SDK-style project (`IncludeBuildOutput=false`, `SuppressDependenciesWhenPacking=true`, `NoWarn=NU5128`), packed with `dotnet pack`. Native files go in via `<None Include="..." Pack="true" PackagePath="runtimes/<rid>/native/" />`. The resulting package has no `lib/` folder and installs into any target framework.
- Because the package ships both `linux-x64` and `linux-musl-x64`, Alpine gets the musl file. Confirm the RID fallback picks it, not the glibc one.
- Include `THIRD-PARTY-NOTICES.md` with the licences: libjxl BSD-3-Clause, brotli MIT, highway Apache-2.0 / BSD-3-Clause, skcms BSD-3-Clause.
- Package metadata: id `LibJxl.Native`, license expression `BSD-3-Clause AND MIT`, description naming the libjxl version and RIDs, `README.md` as the package readme, and tags such as `jpegxl jxl native`.

## Tests

**Every RID that ships is tested on that RID; nothing is packed untested.** The test-only harness is a small `net10.0` console with the P/Invoke it needs. For each RID it:

- Loads the freshly built library.
- Encodes and decodes four 2048×2048 test images and asserts the round trip is bit-exact: photo-like RGB (gradients with photographic noise, flat blocks, hard-edged checkerboards), pure noise, flat palette art, and photo-like RGBA with opaque, transparent and graded alpha. They are generated deterministically in `tests/Harness/TestImages.cs` rather than committed: raw files would be 12–16 MB each, and PNGs would need an image library.
- Reports the median of 10 effort-1 encodes of the photo-like image, for the performance criterion.
- Checks the library's dependencies against the allowed list.

Where each RID runs:

| RID | Test host |
|---|---|
| `linux-x64`, `linux-arm64` | `mcr.microsoft.com/dotnet/sdk:10.0` in Docker (x64 emulated) |
| `linux-musl-x64`, `linux-musl-arm64` | `mcr.microsoft.com/dotnet/sdk:10.0-alpine` in Docker (x64 emulated) |
| `osx-arm64` | Mac host |
| `osx-x64` | Mac host under Rosetta, with an x64 .NET runtime |
| `win-x64` | GitHub `windows-2025` runner |
| `win-arm64` | GitHub `windows-11-arm` runner |

`test.sh <rid>|all` runs the Docker and Mac tests. `Harness.dll --dump <dir>` writes each encoded `.jxl` and its source pixels, for cross-checking with `djxl`.

**djxl cross-check (2026-11-06):** the 24 `.jxl` files encoded on the six non-Windows RIDs all decode with Homebrew's `djxl` v0.12.0 to exactly the source pixels. The encoded bytes are identical across RIDs except `osx-x64` under Rosetta, which picks a different SIMD target and so makes slightly different (still lossless) encoder choices. Windows is still to do. Running x64 binaries under emulation proves they load and round-trip correctly, but performance is only measured natively on `osx-arm64`.

### Windows workflow

`.github/workflows/windows.yml`, triggered only by `workflow_dispatch` (`gh workflow run windows.yml --ref <commit>`):

1. On `ubuntu-24.04`, run `build.sh win-x64 win-arm64` in Docker and upload both DLLs as one artifact.
2. On `windows-2025` and `windows-11-arm`, download that artifact and run the harness (`test.ps1`), then upload each DLL that passed, with its `build-info.txt` and `test-result.txt`, as `windows-tested-<rid>`.
3. *(Once packaging exists.)* On the same runners, pack a Windows-only `.nupkg` and smoke-test it from a local folder source, proving `runtimes/win-*/native/` resolves.

Locally, `./fetch-windows.sh [run-id]` downloads the `windows-tested-*` artifacts into `artifacts/native/win-*/`, replacing any local Windows build, so the files packed are exactly the ones tested on Windows. Actions are pinned by commit SHA.

The repo must be on GitHub. On a private repo, Windows minutes count double against the plan's quota, and `windows-11-arm` may not be available; check before relying on it. If it isn't, `win-arm64` is not shipped.

## Release (local)

- `pack.sh` takes `artifacts/native/<rid>/`, refuses to pack if any RID lacks a passing test result (for Windows, a successful workflow run for the current commit), and runs `dotnet pack`.
- It then smoke-tests the `.nupkg` by restoring it from a local folder source into the harness on linux-x64 (glibc) and Alpine in Docker, and on macOS, and running encode → decode there. This proves the runtime resolves the right `runtimes/<rid>/native/` file, which is what the consumer depends on. Windows resolution is covered by the workflow's Windows-only package.
- Publishing is a manual `dotnet nuget push` to the private feed, documented in the README. Tag the commit `v<version>`.

## Harness settings

The harness, and the performance criterion below, use:

- Encode: interleaved 8-bit sRGB, 3 or 4 channels. `JxlEncoderSetFrameLossless`, `uses_original_profile = true`, sRGB colour encoding, `JXL_ENC_FRAME_SETTING_EFFORT = 1`, no parallel runner.
- Decode: 8-bit interleaved output.

## Consumer documentation

`README.md` (also packed as the package readme) tells consumers:

- The library name to P/Invoke (`"jxl_native"`) and which RIDs are included.
- That the exported API is exactly libjxl's public C API at the pinned tag, with a link to that tag's headers. Struct layouts and enums can change between libjxl versions, so a binding must match the package version.
- A minimal `[LibraryImport]` example (e.g. `JxlEncoderVersion`) and a pointer to the harness as a fuller encode/decode example.

## Acceptance criteria

- [ ] The `.nupkg` contains a native library for at least the four required RIDs, each self-contained per the dependency check.
- [ ] The `.nupkg` contains no managed assembly.
- [ ] On every packed RID, on that RID's test host, the harness's encode then decode of the test images is bit-exact. libjxl's `djxl` (any version) decodes the output to the same pixels; check that once by hand.
- [ ] All native libraries are built in Docker, except macOS, which is built on the Mac host. Windows tests need nothing on the Mac beyond `gh`.
- [ ] Lossless effort-1 encode of a 2048×2048 RGB image takes ≤ 20 ms single-threaded on an M-series Mac, close to `cjxl -d 0 -e 1 --num_threads=0`. This confirms an optimised build (release flags, highway SIMD dispatch) rather than serving any one use case.
- [ ] A fresh `dotnet new console` with only this `.nupkg` in a local folder source restores, builds and runs encode → decode on macOS, Windows, glibc Linux and Alpine, with nothing installed on the machine.
- [ ] `README.md` covers the consumer documentation above, and the Mac prerequisites, and how to build, test (including running the Windows workflow), pack, publish to the feed and bump libjxl.

## Out of scope

A managed binding; consumers write their own.
