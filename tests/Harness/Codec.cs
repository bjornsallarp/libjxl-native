namespace Harness;

// Lossless 8-bit sRGB encode/decode with the settings PLAN.md specifies.
internal static unsafe class Codec
{
    public static byte[] Encode(byte[] pixels, int width, int height, int channels, int effort = 1)
    {
        var enc = Jxl.JxlEncoderCreate(0);
        if (enc == 0) throw new InvalidOperationException("JxlEncoderCreate failed");
        try
        {
            Jxl.BasicInfo info;
            Jxl.JxlEncoderInitBasicInfo(&info);
            info.XSize = (uint)width;
            info.YSize = (uint)height;
            info.BitsPerSample = 8;
            info.UsesOriginalProfile = 1;
            info.NumColorChannels = 3;
            info.NumExtraChannels = channels == 4 ? 1u : 0u;
            info.AlphaBits = channels == 4 ? 8u : 0u;
            Check(enc, Jxl.JxlEncoderSetBasicInfo(enc, &info), "SetBasicInfo");

            // JxlColorEncoding is 104 bytes with 8-byte alignment.
            var color = stackalloc long[16];
            Jxl.JxlColorEncodingSetToSRGB(color, 0);
            Check(enc, Jxl.JxlEncoderSetColorEncoding(enc, color), "SetColorEncoding");

            var settings = Jxl.JxlEncoderFrameSettingsCreate(enc, 0);
            Check(enc, Jxl.JxlEncoderSetFrameLossless(settings, 1), "SetFrameLossless");
            Check(enc, Jxl.JxlEncoderFrameSettingsSetOption(settings, Jxl.EncFrameSettingEffort, effort), "SetOption(effort)");

            var format = new Jxl.PixelFormat { NumChannels = (uint)channels, DataType = Jxl.TypeUint8, Endianness = Jxl.NativeEndian };
            fixed (byte* p = pixels)
                Check(enc, Jxl.JxlEncoderAddImageFrame(settings, &format, p, (nuint)pixels.Length), "AddImageFrame");
            Jxl.JxlEncoderCloseInput(enc);

            var output = new byte[Math.Max(pixels.Length / 4, 4096)];
            var used = 0;
            while (true)
            {
                int status;
                fixed (byte* start = output)
                {
                    var next = start + used;
                    var avail = (nuint)(output.Length - used);
                    status = Jxl.JxlEncoderProcessOutput(enc, &next, &avail);
                    used = (int)(next - start);
                }
                if (status == Jxl.EncSuccess) break;
                if (status != Jxl.EncNeedMoreOutput) Check(enc, status, "ProcessOutput");
                Array.Resize(ref output, output.Length * 2);
            }
            Array.Resize(ref output, used);
            return output;
        }
        finally
        {
            Jxl.JxlEncoderDestroy(enc);
        }
    }

    public static (byte[] Pixels, int Width, int Height, int Channels) Decode(byte[] jxl)
    {
        var dec = Jxl.JxlDecoderCreate(0);
        if (dec == 0) throw new InvalidOperationException("JxlDecoderCreate failed");
        try
        {
            Expect(Jxl.JxlDecoderSubscribeEvents(dec, Jxl.DecBasicInfo | Jxl.DecFullImage), "SubscribeEvents");
            fixed (byte* input = jxl)
            {
                Expect(Jxl.JxlDecoderSetInput(dec, input, (nuint)jxl.Length), "SetInput");
                Jxl.JxlDecoderCloseInput(dec);

                Jxl.BasicInfo info = default;
                var format = new Jxl.PixelFormat { DataType = Jxl.TypeUint8, Endianness = Jxl.NativeEndian };
                byte[]? pixels = null;
                while (true)
                {
                    var status = Jxl.JxlDecoderProcessInput(dec);
                    switch (status)
                    {
                        case Jxl.DecBasicInfo:
                            Expect(Jxl.JxlDecoderGetBasicInfo(dec, &info), "GetBasicInfo");
                            format.NumChannels = info.AlphaBits > 0 ? 4u : 3u;
                            break;
                        case Jxl.DecNeedImageOutBuffer:
                            nuint size;
                            Expect(Jxl.JxlDecoderImageOutBufferSize(dec, &format, &size), "ImageOutBufferSize");
                            // The decoder writes into this buffer across later calls, so it must not move.
                            pixels = GC.AllocateUninitializedArray<byte>((int)size, pinned: true);
                            fixed (byte* p = pixels)
                                Expect(Jxl.JxlDecoderSetImageOutBuffer(dec, &format, p, size), "SetImageOutBuffer");
                            break;
                        case Jxl.DecFullImage:
                            break;
                        case Jxl.DecSuccess:
                            return (pixels ?? throw new InvalidOperationException("no image decoded"),
                                (int)info.XSize, (int)info.YSize, (int)format.NumChannels);
                        default:
                            throw new InvalidOperationException($"JxlDecoderProcessInput returned {status}");
                    }
                }
            }
        }
        finally
        {
            Jxl.JxlDecoderDestroy(dec);
        }
    }

    private static void Check(nint enc, int status, string call)
    {
        if (status != Jxl.EncSuccess)
            throw new InvalidOperationException($"JxlEncoder{call} failed: status {status}, error {Jxl.JxlEncoderGetError(enc)}");
    }

    private static void Expect(int status, string call)
    {
        if (status != Jxl.DecSuccess)
            throw new InvalidOperationException($"JxlDecoder{call} failed: status {status}");
    }
}
