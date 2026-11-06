using System.Runtime.InteropServices;

namespace Harness;

// Only the subset of libjxl's C API the harness needs; layouts match libjxl v0.12.0.
internal static unsafe partial class Jxl
{
    public const string Lib = "jxl_native";

    public const int EncSuccess = 0, EncNeedMoreOutput = 2;
    public const int EncFrameSettingEffort = 0;

    public const int DecSuccess = 0, DecError = 1, DecNeedMoreInput = 2, DecNeedImageOutBuffer = 5;
    public const int DecBasicInfo = 0x40, DecFullImage = 0x1000;

    public const int TypeUint8 = 2, NativeEndian = 0;

    [StructLayout(LayoutKind.Sequential)]
    public struct PixelFormat
    {
        public uint NumChannels;
        public int DataType;
        public int Endianness;
        public nuint Align;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct BasicInfo
    {
        public int HaveContainer;
        public uint XSize, YSize;
        public uint BitsPerSample, ExponentBitsPerSample;
        public float IntensityTarget, MinNits;
        public int RelativeToMaxDisplay;
        public float LinearBelow;
        public int UsesOriginalProfile, HavePreview, HaveAnimation;
        public int Orientation;
        public uint NumColorChannels, NumExtraChannels;
        public uint AlphaBits, AlphaExponentBits;
        public int AlphaPremultiplied;
        public uint PreviewXSize, PreviewYSize;
        public uint TpsNumerator, TpsDenominator, NumLoops;
        public int HaveTimecodes;
        public uint IntrinsicXSize, IntrinsicYSize;
        public fixed byte Padding[100];
    }

    [LibraryImport(Lib)] public static partial uint JxlEncoderVersion();
    [LibraryImport(Lib)] public static partial uint JxlDecoderVersion();

    [LibraryImport(Lib)] public static partial nint JxlEncoderCreate(nint memoryManager);
    [LibraryImport(Lib)] public static partial void JxlEncoderDestroy(nint enc);
    [LibraryImport(Lib)] public static partial int JxlEncoderGetError(nint enc);
    [LibraryImport(Lib)] public static partial void JxlEncoderInitBasicInfo(BasicInfo* info);
    [LibraryImport(Lib)] public static partial int JxlEncoderSetBasicInfo(nint enc, BasicInfo* info);
    // JxlColorEncoding is passed as an opaque buffer; the harness never reads its fields.
    [LibraryImport(Lib)] public static partial void JxlColorEncodingSetToSRGB(void* colorEncoding, int isGray);
    [LibraryImport(Lib)] public static partial int JxlEncoderSetColorEncoding(nint enc, void* colorEncoding);
    [LibraryImport(Lib)] public static partial nint JxlEncoderFrameSettingsCreate(nint enc, nint source);
    [LibraryImport(Lib)] public static partial int JxlEncoderSetFrameLossless(nint settings, int lossless);
    [LibraryImport(Lib)] public static partial int JxlEncoderFrameSettingsSetOption(nint settings, int option, long value);
    [LibraryImport(Lib)] public static partial int JxlEncoderAddImageFrame(nint settings, PixelFormat* format, void* buffer, nuint size);
    [LibraryImport(Lib)] public static partial void JxlEncoderCloseInput(nint enc);
    [LibraryImport(Lib)] public static partial int JxlEncoderProcessOutput(nint enc, byte** nextOut, nuint* availOut);

    [LibraryImport(Lib)] public static partial nint JxlDecoderCreate(nint memoryManager);
    [LibraryImport(Lib)] public static partial void JxlDecoderDestroy(nint dec);
    [LibraryImport(Lib)] public static partial int JxlDecoderSubscribeEvents(nint dec, int eventsWanted);
    [LibraryImport(Lib)] public static partial int JxlDecoderSetInput(nint dec, byte* data, nuint size);
    [LibraryImport(Lib)] public static partial void JxlDecoderCloseInput(nint dec);
    [LibraryImport(Lib)] public static partial int JxlDecoderProcessInput(nint dec);
    [LibraryImport(Lib)] public static partial int JxlDecoderGetBasicInfo(nint dec, BasicInfo* info);
    [LibraryImport(Lib)] public static partial int JxlDecoderImageOutBufferSize(nint dec, PixelFormat* format, nuint* size);
    [LibraryImport(Lib)] public static partial int JxlDecoderSetImageOutBuffer(nint dec, PixelFormat* format, void* buffer, nuint size);
}
