# MightyLittleJxl.Native

Native builds of [libjxl](https://github.com/libjxl/libjxl) 0.12.0, the JPEG XL reference library, packaged for .NET P/Invoke. Each runtime gets one self-contained library that exports libjxl's full C API. The package has no managed code: you write the binding you need.

## Using the package

```sh
dotnet add package MightyLittleJxl.Native --version 0.12.0
```

The package has no other dependencies and works with any target framework. .NET picks the right file for the platform from `runtimes/<rid>/native/`, with musl preferred over glibc on Alpine.

| RID | File | Requires |
|---|---|---|
| `linux-x64`, `linux-arm64` | `libjxl_native.so` | glibc 2.27 or newer |
| `linux-musl-x64`, `linux-musl-arm64` | `libjxl_native.so` | musl (Alpine) |
| `osx-x64`, `osx-arm64` | `libjxl_native.dylib` | macOS 13 or newer |
| `win-x64`, `win-arm64` | `jxl_native.dll` | Windows 10 or newer |

Each library links libjxl, its dependencies (Highway, Brotli, skcms) and the C++ runtime statically, and depends only on the operating system's own libraries. The name `jxl_native` is deliberately unique, so a system libjxl (Homebrew, apt, apk) is never loaded by mistake.

### Binding

Import from `"jxl_native"`:

```csharp
using System.Runtime.InteropServices;

static partial class Jxl
{
    [LibraryImport("jxl_native")]
    public static partial uint JxlEncoderVersion(); // 12000 for 0.12.0
}
```

`[LibraryImport]` needs `<AllowUnsafeBlocks>true</AllowUnsafeBlocks>` in your project; `[DllImport]` works too.

The exported API is exactly libjxl's public C API at [v0.12.0](https://github.com/libjxl/libjxl/tree/v0.12.0/lib/include/jxl): the encoder and decoder (`jxl/encode.h`, `jxl/decode.h`), the colour management system (`jxl/cms.h`) and both thread runners (`jxl/thread_parallel_runner.h`, `jxl/resizable_parallel_runner.h`). That's 115 functions, the same set upstream's own shared libraries export. `jxl/gain_map.h` and `jxl/compressed_icc.h` are not included, because upstream builds them into a separate extras library.

Struct layouts and enums can change between libjxl versions, so write your binding against the headers of the libjxl version the package version names.

For a fuller example, see the [test harness](https://github.com/bjornsallarp/libjxl-native/tree/main/tests/Harness). It does a lossless 8-bit encode and decode (`Jxl.cs`, `Codec.cs`) and is tested on every runtime.

### Licence

libjxl and Highway are BSD-3-Clause, Brotli is MIT, and skcms is BSD-3-Clause. The Windows libraries also contain the LLVM and MinGW-w64 runtimes. Full texts are in [`THIRD-PARTY-NOTICES.md`](https://github.com/bjornsallarp/libjxl-native/blob/main/THIRD-PARTY-NOTICES.md), which is also in the package.

## How it's built and released

Everything runs on GitHub Actions; [`PLAN.md`](https://github.com/bjornsallarp/libjxl-native/blob/main/PLAN.md) has the full requirements and design decisions. Inputs are pinned in [`versions.env`](https://github.com/bjornsallarp/libjxl-native/blob/main/versions.env): the libjxl tag and commit, and every build and test image by digest.

[`ci.yml`](https://github.com/bjornsallarp/libjxl-native/blob/main/.github/workflows/ci.yml) runs on every push and pull request:

1. **Build and test** each runtime on a runner of its own platform. The build fails if the exported functions don't match libjxl's public headers, or if the library depends on anything outside its allowed list. The test round-trips four 2048×2048 images losslessly and checks every byte.
2. **Cross-check** every encoded file with libjxl's own `djxl`, which must decode it to exactly the source pixels.
3. **Pack** the eight tested libraries into the `.nupkg`.
4. **Smoke-test the package** on all eight runtimes: a fresh project restores it from a local folder and encodes and decodes, with .NET picking the library from `runtimes/<rid>/native/`.
5. **Release**, on `main` only: if this package version isn't released yet, push it to nuget.org and create a GitHub release with the `.nupkg` attached.

[`update.yml`](https://github.com/bjornsallarp/libjxl-native/blob/main/.github/workflows/update.yml) checks weekly for a new libjxl release. When there is one, it opens a pull request that bumps `versions.env` and runs CI on it. Merging the pull request releases the new version.

To repack the same libjxl, for example after a build fix, add `PACKAGE_VERSION=<libjxl version>.1` to `versions.env` and merge.

### Setup

- nuget.org [Trusted Publishing](https://learn.microsoft.com/nuget/nuget-org/trusted-publishing) policy for `MightyLittleJxl.*`: repository `bjornsallarp/libjxl-native`, workflow `ci.yml`, environment `nuget`. No API key is stored; each release run gets a short-lived one.
- GitHub environment `nuget`, deployable from `main` only.
- Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests", so `update.yml` can open its pull request.

### Running locally

The same scripts run on an Apple silicon Mac, for debugging. Prerequisites: Docker Desktop with Rosetta emulation for amd64, Rosetta 2, Xcode Command Line Tools, `cmake` and `ninja`, the .NET 10 SDK, and `djxl` (`brew install jpeg-xl`).

| Step | Command |
|---|---|
| Build | `./build.sh [<rid>...]`, all eight by default (Windows cross-compiles in Docker) → `artifacts/native/<rid>/` |
| Test | `./test.sh [<rid>...]`, Linux in Docker and macOS on the Mac. Windows only runs in CI (`test.ps1`). |
| Cross-check | `scripts/djxl-check.sh build/dump` |
| Pack | `./pack.sh` → `artifacts/package/MightyLittleJxl.Native.<version>.nupkg` (needs a passing test for every runtime present) |
| Smoke-test | `./smoke.sh [<rid>...]` |
