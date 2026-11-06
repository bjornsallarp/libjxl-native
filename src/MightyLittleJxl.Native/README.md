# MightyLittleJxl.Native

Native builds of [libjxl](https://github.com/libjxl/libjxl) 0.12.0, the JPEG XL reference library, for .NET P/Invoke. Each runtime gets one self-contained library that exports libjxl's full C API. The package has no managed code: you write the binding you need.

## Runtimes

| RID | File | Requires |
|---|---|---|
| `linux-x64`, `linux-arm64` | `libjxl_native.so` | glibc 2.27 or newer |
| `linux-musl-x64`, `linux-musl-arm64` | `libjxl_native.so` | musl (Alpine) |
| `osx-x64`, `osx-arm64` | `libjxl_native.dylib` | macOS 13 or newer |
| `win-x64`, `win-arm64` | `jxl_native.dll` | Windows 10 or newer |

The package has no dependencies and works with any target framework. .NET picks the right file for the platform from `runtimes/<rid>/native/`, preferring musl over glibc on Alpine.

Each library links libjxl, its dependencies (Highway, Brotli, skcms) and the C++ runtime statically, and depends only on the operating system's own libraries. The name `jxl_native` is deliberately unique, so a system libjxl (Homebrew, apt, apk) is never loaded by mistake.

## Binding

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

## How it's made

Every release is built, tested on each runtime, cross-checked against libjxl's own `djxl`, and published by CI at [bjornsallarp/libjxl-native](https://github.com/bjornsallarp/libjxl-native). New libjxl releases are picked up automatically.

## Licence

libjxl and Highway are BSD-3-Clause, Brotli is MIT, and skcms is BSD-3-Clause. The Windows libraries also contain the LLVM and MinGW-w64 runtimes. Full texts are in `THIRD-PARTY-NOTICES.md` in the package and [on GitHub](https://github.com/bjornsallarp/libjxl-native/blob/main/THIRD-PARTY-NOTICES.md).
