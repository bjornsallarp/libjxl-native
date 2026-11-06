# LibJxl.Native

Native builds of [libjxl](https://github.com/libjxl/libjxl) 0.12.0, the JPEG XL reference library, packaged for .NET P/Invoke. Each runtime gets one self-contained library that exports libjxl's full C API. The package has no managed code: you write the binding you need.

## Using the package

```sh
dotnet add package LibJxl.Native --version 0.12.0
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

The exported API is exactly libjxl's public C API at [v0.12.0](https://github.com/libjxl/libjxl/tree/v0.12.0/lib/include/jxl): the encoder and decoder (`jxl/encode.h`, `jxl/decode.h`), the colour management system (`jxl/cms.h`) and both thread runners (`jxl/thread_parallel_runner.h`, `jxl/resizable_parallel_runner.h`). That's 115 functions, the same set upstream's own shared libraries export. `jxl/gain_map.h` and `jxl/compressed_icc.h` are not included, because upstream builds them into a separate extras library.

Struct layouts and enums can change between libjxl versions, so write your binding against the headers of the libjxl version the package version names.

For a fuller example, see the [test harness](https://github.com/bjornsallarp/libjxl-native/tree/main/tests/Harness). It does a lossless 8-bit encode and decode (`Jxl.cs`, `Codec.cs`) and is tested on every runtime.

### Licence

libjxl and Highway are BSD-3-Clause, Brotli is MIT, and skcms is BSD-3-Clause. The Windows libraries also contain the LLVM and MinGW-w64 runtimes. Full texts are in [`THIRD-PARTY-NOTICES.md`](https://github.com/bjornsallarp/libjxl-native/blob/main/THIRD-PARTY-NOTICES.md), which is also in the package.

## Building

Everything builds on an Apple silicon Mac: Linux and Windows in Docker, macOS natively. Windows is tested on GitHub-hosted runners. [`PLAN.md`](https://github.com/bjornsallarp/libjxl-native/blob/main/PLAN.md) has the full requirements and design decisions.

**Prerequisites:** Docker Desktop with Rosetta emulation for amd64, Rosetta 2, Xcode Command Line Tools, `cmake` and `ninja` (Homebrew), the .NET 10 SDK, `gh` logged in to an account that can run this repo's workflows, and `djxl` (`brew install jpeg-xl`) for the cross-check.

Inputs are pinned in [`versions.env`](https://github.com/bjornsallarp/libjxl-native/blob/main/versions.env): the libjxl tag and commit, and the base images by digest.

| Step | Command |
|---|---|
| Build, macOS and Linux | `./build.sh` (or `./build.sh <rid>...`) → `artifacts/native/<rid>/` |
| Test, macOS and Linux | `./test.sh` (or `./test.sh <rid>...`); osx-x64 runs under Rosetta |
| Build and test Windows | `gh workflow run windows.yml --ref main`, then `./fetch-windows.sh` once it passes |
| Cross-check with djxl | `dotnet build/harness/Harness.dll --dump <dir>` per RID, then `scripts/djxl-check.sh <dir>` |
| Pack and smoke-test | `./pack.sh` → `artifacts/package/LibJxl.Native.<version>.nupkg` |

`build.sh` fails if the exported functions don't match libjxl's public headers, or if a library depends on anything outside its allowed list. `pack.sh` refuses to pack a runtime without a passing test result. It then restores the `.nupkg` from a local folder into a copy of the harness and runs it on every Linux and macOS runtime. The Windows workflow does the same on Windows.

### Releasing

1. Build, test and pack as above, on a clean commit.
2. Push to the feed:
   ```sh
   dotnet nuget push artifacts/package/LibJxl.Native.<version>.nupkg --source <feed> --api-key <key>
   ```
3. Tag the commit `v<version>` and push the tag.

### Bumping libjxl

1. Set `LIBJXL_TAG` and `LIBJXL_COMMIT` in `versions.env`. Get the commit with `git ls-remote https://github.com/libjxl/libjxl.git refs/tags/<tag>`.
2. Delete `build/` so the source is fetched again.
3. Build, test and pack everything as above. The package version follows the tag.
4. If the export check fails, compare the new public headers with the export list in `scripts/build-native.sh`, and update the README's export count.

To repack the same libjxl, for example after a build fix, pass a fourth version part: `./pack.sh -p:PackageVersion=0.12.0.1`.
