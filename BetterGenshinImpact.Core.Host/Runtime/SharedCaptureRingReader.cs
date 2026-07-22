using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.Model.Area.Converter;
using Newtonsoft.Json.Linq;
using OpenCvSharp;
using System.IO.MemoryMappedFiles;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;

namespace BetterGenshinImpact.Core.Host.Runtime;

[SupportedOSPlatform("macos")]
public sealed class SharedCaptureRingReader(
    RuntimeLayout layout,
    Func<DesktopRegion>? desktopRegionProvider = null)
{
    private const long HeaderSize = 128;
    private static readonly byte[] Magic = Encoding.ASCII.GetBytes("BGIRING1");

    public GameCaptureRegion Read(JToken response)
    {
        var path = RequiredString(response, "ringPath");
        var expectedPath = Path.Combine(layout.RunPath, "capture-ring.bin");
        if (Path.GetFullPath(path) != expectedPath)
            throw new InvalidDataException("capture.request returned a ring outside the runtime Run directory.");
        if (!File.Exists(path)) throw new FileNotFoundException("Capture ring does not exist.", path);
        var mode = File.GetUnixFileMode(path);
        if (mode != (UnixFileMode.UserRead | UnixFileMode.UserWrite))
            throw new InvalidDataException($"Capture ring mode must be 0600, got {mode}.");

        using var mapped = MemoryMappedFile.CreateFromFile(path, FileMode.Open, null, 0, MemoryMappedFileAccess.Read);
        using var view = mapped.CreateViewAccessor(0, 0, MemoryMappedFileAccess.Read);
        var magic = new byte[Magic.Length];
        view.ReadArray(0, magic, 0, magic.Length);
        if (!magic.SequenceEqual(Magic)) throw new InvalidDataException("Capture ring magic is invalid.");
        if (view.ReadUInt32(8) != 1) throw new InvalidDataException("Capture ring version is unsupported.");
        if (view.ReadUInt32(12) != 2) throw new InvalidDataException("Capture ring slot count is invalid.");

        var slotCapacity = checked((long)view.ReadUInt64(16));
        var slot = checked((int)view.ReadUInt32(24));
        var width = checked((int)view.ReadUInt32(28));
        var height = checked((int)view.ReadUInt32(32));
        var stride = checked((int)view.ReadUInt32(36));
        var pixelFormat = view.ReadUInt32(40);
        var dataLength = checked((long)view.ReadUInt64(48));
        var frameId = view.ReadUInt64(56);
        var captureX = view.ReadInt32(64);
        var captureY = view.ReadInt32(68);
        var sequenceBefore = view.ReadUInt64(80);

        if ((sequenceBefore & 1) != 0) throw new InvalidDataException("Capture ring frame is still being written.");
        if (slot is < 0 or >= 2 || slotCapacity <= 0)
            throw new InvalidDataException("Capture ring slot metadata is invalid.");
        if (width <= 0 || height <= 0 || width > 16384 || height > 16384)
            throw new InvalidDataException("Capture frame dimensions are invalid.");
        if (stride < checked(width * 4) || dataLength != checked((long)stride * height) || dataLength > slotCapacity)
            throw new InvalidDataException("Capture frame stride or data length is invalid.");
        if (pixelFormat != 0x42475241 || RequiredString(response, "pixelFormat") != "BGRA8")
            throw new InvalidDataException("Capture frame pixel format must be BGRA8.");
        if (RequiredUInt64(response, "frameId") != frameId || RequiredUInt64(response, "sequence") != sequenceBefore)
            throw new InvalidDataException("capture.request metadata does not match the ring header.");
        if (RequiredInt(response, "width") != width || RequiredInt(response, "height") != height ||
            RequiredInt(response, "stride") != stride || RequiredInt(response, "slot") != slot)
            throw new InvalidDataException("capture.request dimensions do not match the ring header.");

        var source = HeaderSize + checked(slot * slotCapacity);
        var row = new byte[stride];
        var mat = new Mat(height, width, MatType.CV_8UC4);
        try
        {
            for (var y = 0; y < height; y++)
            {
                view.ReadArray(source + (long)y * stride, row, 0, stride);
                Marshal.Copy(row, 0, mat.Data + checked((int)(y * mat.Step())), width * 4);
            }
            var sequenceAfter = view.ReadUInt64(80);
            if (sequenceAfter != sequenceBefore || (sequenceAfter & 1) != 0)
                throw new InvalidDataException("Capture ring frame changed while it was being read.");
            var desktop = desktopRegionProvider?.Invoke() ?? new DesktopRegion(width, height);
            return new GameCaptureRegion(
                mat, captureX, captureY, desktop, new TranslationConverter(captureX, captureY));
        }
        catch
        {
            mat.Dispose();
            throw;
        }
    }

    private static string RequiredString(JToken token, string name) =>
        token.Value<string>(name) is { Length: > 0 } value
            ? value : throw new InvalidDataException($"capture.request omitted {name}.");
    private static int RequiredInt(JToken token, string name) =>
        token.Value<int?>(name) ?? throw new InvalidDataException($"capture.request omitted {name}.");
    private static ulong RequiredUInt64(JToken token, string name) =>
        token.Value<ulong?>(name) ?? throw new InvalidDataException($"capture.request omitted {name}.");
}
