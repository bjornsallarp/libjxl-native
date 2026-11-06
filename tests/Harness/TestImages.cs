namespace Harness;

// Deterministic 2048x2048 test images, generated rather than committed: a raw
// 2048x2048 image is 12-16 MB, and a PNG would need an image library to read.
internal static class TestImages
{
    public const int Size = 2048;

    public static IEnumerable<(string Name, byte[] Pixels, int Channels)> All()
    {
        yield return ("rgb-photo", Photo(3, seed: 1), 3);
        yield return ("rgb-noise", Noise(3, seed: 2), 3);
        yield return ("rgb-flat", Flat(3, seed: 3), 3);
        yield return ("rgba-photo", Photo(4, seed: 4), 4);
    }

    // Smooth gradients with photographic noise, plus flat blocks and hard-edged checkerboards.
    public static byte[] Photo(int channels, ulong seed)
    {
        var rng = new SplitMix64(seed);
        var px = new byte[Size * Size * channels];
        for (var y = 0; y < Size; y++)
        for (var x = 0; x < Size; x++)
        {
            var i = (y * Size + x) * channels;
            var block = (x / 256 + y / 256 * 8) % 7;
            if (block == 0)
            {
                // Flat region: one colour per 256x256 block.
                var c = (byte)(x / 256 * 31 + y / 256 * 17);
                px[i] = c; px[i + 1] = (byte)(c * 3); px[i + 2] = (byte)(255 - c);
            }
            else if (block == 1)
            {
                var on = ((x / 8) ^ (y / 8)) & 1;
                px[i] = px[i + 1] = px[i + 2] = (byte)(on * 255);
            }
            else
            {
                var n = rng.Gaussian() * 6;
                px[i] = Clamp(x / 8.0 + n);
                px[i + 1] = Clamp(y / 8.0 + n * 0.8 + rng.Gaussian() * 2);
                px[i + 2] = Clamp((x + y) / 16.0 + 64 * Math.Sin(x / 97.0) + n * 1.2);
            }
            if (channels == 4)
            {
                // Opaque, fully transparent and graded alpha regions.
                px[i + 3] = (y / 512) switch { 0 => 255, 1 => 0, 2 => (byte)(x / 8), _ => (byte)rng.Next() };
            }
        }
        return px;
    }

    public static byte[] Noise(int channels, ulong seed)
    {
        var rng = new SplitMix64(seed);
        var px = new byte[Size * Size * channels];
        for (var i = 0; i < px.Length; i += 8)
            BitConverter.TryWriteBytes(px.AsSpan(i), rng.Next());
        return px;
    }

    // Large areas from a small palette, as in UI art or textures.
    public static byte[] Flat(int channels, ulong seed)
    {
        var rng = new SplitMix64(seed);
        var palette = new byte[16 * 3];
        for (var i = 0; i < palette.Length; i++) palette[i] = (byte)rng.Next();
        var px = new byte[Size * Size * channels];
        for (var y = 0; y < Size; y++)
        for (var x = 0; x < Size; x++)
        {
            var i = (y * Size + x) * channels;
            var p = ((x / 64 * 7 + y / 64 * 13) & 15) * 3;
            px[i] = palette[p]; px[i + 1] = palette[p + 1]; px[i + 2] = palette[p + 2];
        }
        return px;
    }

    private static byte Clamp(double v) => (byte)Math.Clamp((int)Math.Round(v), 0, 255);

    private struct SplitMix64(ulong state)
    {
        public ulong Next()
        {
            var z = state += 0x9E3779B97F4A7C15;
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EB;
            return z ^ (z >> 31);
        }

        // Approximate normal distribution: sum of four uniforms, centred.
        public double Gaussian()
        {
            double s = 0;
            for (var k = 0; k < 4; k++) s += (Next() >> 11) * (1.0 / (1UL << 53));
            return (s - 2) * 1.7320508;
        }
    }
}
