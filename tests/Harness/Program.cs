using System.Diagnostics;
using System.Runtime.InteropServices;
using Harness;

// JXL_NATIVE_PATH points at a freshly built library; without it, normal
// resolution applies (runtimes/<rid>/native/ from the package).
var nativePath = Environment.GetEnvironmentVariable("JXL_NATIVE_PATH");
if (!string.IsNullOrEmpty(nativePath))
{
    NativeLibrary.SetDllImportResolver(typeof(Jxl).Assembly,
        (name, _, _) => name == Jxl.Lib ? NativeLibrary.Load(nativePath) : 0);
}

Console.WriteLine($"runtime: {RuntimeInformation.RuntimeIdentifier} ({RuntimeInformation.OSDescription}, {RuntimeInformation.ProcessArchitecture})");
var v = Jxl.JxlEncoderVersion();
// On Linux, show which file the runtime actually loaded, e.g. musl vs glibc from the package.
var loaded = nativePath;
if (string.IsNullOrEmpty(loaded) && OperatingSystem.IsLinux())
    loaded = File.ReadLines("/proc/self/maps").Select(l => l.Split(' ', StringSplitOptions.RemoveEmptyEntries))
        .Select(p => p[^1]).FirstOrDefault(p => p.EndsWith("libjxl_native.so"));
Console.WriteLine($"library: {loaded ?? "(package)"}");
Console.WriteLine($"libjxl: {v / 1000000}.{v / 1000 % 1000}.{v % 1000}");

// --dump <dir> writes each encoded .jxl and its source pixels (.raw), for
// cross-checking with libjxl's own djxl.
var dumpDir = args is ["--dump", var d] ? Directory.CreateDirectory(d).FullName : null;

var failed = 0;
foreach (var (name, pixels, channels) in TestImages.All())
{
    var sw = Stopwatch.StartNew();
    var jxl = Codec.Encode(pixels, TestImages.Size, TestImages.Size, channels);
    var encodeMs = sw.Elapsed.TotalMilliseconds;
    if (dumpDir != null)
    {
        File.WriteAllBytes(Path.Combine(dumpDir, $"{name}.jxl"), jxl);
        File.WriteAllBytes(Path.Combine(dumpDir, $"{name}.raw"), pixels);
    }
    sw.Restart();
    var (decoded, width, height, decodedChannels) = Codec.Decode(jxl);
    var decodeMs = sw.Elapsed.TotalMilliseconds;

    var ok = width == TestImages.Size && height == TestImages.Size && decodedChannels == channels
        && decoded.AsSpan().SequenceEqual(pixels);
    if (!ok) failed++;
    Console.WriteLine($"{(ok ? "PASS" : "FAIL")} {name,-11} {pixels.Length / 1024,6} KB -> {jxl.Length / 1024,6} KB  encode {encodeMs,7:F1} ms  decode {decodeMs,7:F1} ms");
    if (!ok)
    {
        var at = decoded.AsSpan().CommonPrefixLength(pixels);
        Console.WriteLine($"     got {width}x{height}x{decodedChannels}, first difference at byte {at}");
    }
}

// Steady-state single-threaded encode time, for PLAN.md's performance criterion.
var photo = TestImages.Photo(3, seed: 1);
var times = new List<double>();
for (var i = 0; i < 10; i++)
{
    var sw = Stopwatch.StartNew();
    Codec.Encode(photo, TestImages.Size, TestImages.Size, 3);
    times.Add(sw.Elapsed.TotalMilliseconds);
}
times.Sort();
Console.WriteLine($"rgb-photo effort-1 encode, median of 10: {times[5]:F1} ms");

Console.WriteLine(failed == 0 ? "OK" : $"{failed} FAILED");
return failed == 0 ? 0 : 1;
