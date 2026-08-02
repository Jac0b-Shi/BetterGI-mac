using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.Model.Area.Converter;
using Microsoft.Win32.SafeHandles;
using Newtonsoft.Json.Linq;
using OpenCvSharp;
using System.IO.MemoryMappedFiles;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;
using System.Text.RegularExpressions;

namespace BetterGenshinImpact.Core.Host.Runtime;

[SupportedOSPlatform("macos")]
public sealed class CaptureRingConsistencyException : IOException
{
    public CaptureRingConsistencyException(string message) : base(message)
    {
    }
}

[SupportedOSPlatform("macos")]
public sealed class SharedCaptureRingReader(
    RuntimeLayout layout,
    Func<DesktopRegion>? desktopRegionProvider = null,
    bool allowFileFixture = false)
{
    private const long HeaderSize = 128;
    private const int OpenReadOnly = 0;
    private const int ProtectRead = 0x01;
    private const int MapShared = 0x0001;
    private static readonly byte[] Magic = Encoding.ASCII.GetBytes("BGIRING1");

    public GameCaptureRegion ReadLatest(
        Func<JToken> responseProvider,
        int maxAttempts = 3)
    {
        ArgumentNullException.ThrowIfNull(responseProvider);
        if (maxAttempts <= 0)
            throw new ArgumentOutOfRangeException(nameof(maxAttempts));

        for (var attempt = 1; ; attempt++)
        {
            try
            {
                return Read(responseProvider());
            }
            catch (CaptureRingConsistencyException) when (attempt < maxAttempts)
            {
            }
        }
    }

    public GameCaptureRegion Read(JToken response)
    {
        if (response.Value<string>("ringName") is { Length: > 0 } name)
            return ReadSharedMemory(name, response);
        if (allowFileFixture &&
            response.Value<string>("ringPath") is { Length: > 0 } path)
            return ReadFileFixture(path, response);
        throw new InvalidDataException(
            "capture.request omitted the POSIX shared-memory ring name.");
    }

    private GameCaptureRegion ReadSharedMemory(string name, JToken response)
    {
        if (!SharedMemoryNamePattern().IsMatch(name))
            throw new InvalidDataException("capture.request returned an invalid shared-memory ring name.");

        var descriptor = ShmOpen(name, OpenReadOnly, 0);
        if (descriptor < 0)
            throw new IOException(
                $"Unable to open capture shared memory '{name}': " +
                Marshal.GetLastPInvokeErrorMessage());
        using var handle = new SafeFileHandle((IntPtr)descriptor, ownsHandle: true);
        using var header = PosixMappedView.Open(
            descriptor, HeaderSize, ProtectRead, MapShared);
        var slotCapacity = checked((long)header.ReadUInt64(16));
        if (slotCapacity <= 0 || slotCapacity > 1L << 30)
            throw new InvalidDataException(
                "Capture shared-memory slot capacity is invalid.");
        var mappingLength = checked(HeaderSize + 2 * slotCapacity);
        using var view = PosixMappedView.Open(
            descriptor, mappingLength, ProtectRead, MapShared);
        return ReadView(view, response);
    }

    private GameCaptureRegion ReadFileFixture(string path, JToken response)
    {
        var expectedPath = Path.Combine(layout.RunPath, "capture-ring.bin");
        if (Path.GetFullPath(path) != expectedPath)
            throw new InvalidDataException(
                "capture.request returned a fixture ring outside the runtime Run directory.");
        if (!File.Exists(path))
            throw new FileNotFoundException("Capture ring fixture does not exist.", path);
        var mode = File.GetUnixFileMode(path);
        if (mode != (UnixFileMode.UserRead | UnixFileMode.UserWrite))
            throw new InvalidDataException($"Capture ring fixture mode must be 0600, got {mode}.");

        using var mapped = MemoryMappedFile.CreateFromFile(
            path, FileMode.Open, null, 0, MemoryMappedFileAccess.Read);
        using var accessor = mapped.CreateViewAccessor(
            0, 0, MemoryMappedFileAccess.Read);
        var view = new AccessorView(accessor);
        return ReadView(view, response);
    }

    private GameCaptureRegion ReadView(
        IReadView view,
        JToken response)
    {
        var magic = new byte[Magic.Length];
        view.ReadArray(0, magic, 0, magic.Length);
        if (!magic.SequenceEqual(Magic))
            throw new InvalidDataException("Capture ring magic is invalid.");
        if (view.ReadUInt32(8) != 1)
            throw new InvalidDataException("Capture ring version is unsupported.");
        if (view.ReadUInt32(12) != 2)
            throw new InvalidDataException("Capture ring slot count is invalid.");

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

        if ((sequenceBefore & 1) != 0)
            throw new CaptureRingConsistencyException(
                "Capture ring frame is still being written.");
        if (slot is < 0 or >= 2 || slotCapacity <= 0)
            throw new InvalidDataException("Capture ring slot metadata is invalid.");
        if (width <= 0 || height <= 0 || width > 16384 || height > 16384)
            throw new InvalidDataException("Capture frame dimensions are invalid.");
        if (stride < checked(width * 4) ||
            dataLength != checked((long)stride * height) ||
            dataLength > slotCapacity)
            throw new InvalidDataException("Capture frame stride or data length is invalid.");
        if (pixelFormat != 0x42475241 ||
            RequiredString(response, "pixelFormat") != "BGRA8")
            throw new InvalidDataException("Capture frame pixel format must be BGRA8.");
        if (RequiredUInt64(response, "frameId") != frameId ||
            RequiredUInt64(response, "sequence") != sequenceBefore)
            throw new CaptureRingConsistencyException(
                "capture.request metadata does not match the ring header.");
        if (RequiredInt(response, "width") != width ||
            RequiredInt(response, "height") != height ||
            RequiredInt(response, "stride") != stride ||
            RequiredInt(response, "slot") != slot)
            throw new CaptureRingConsistencyException(
                "capture.request dimensions do not match the ring header.");

        var source = HeaderSize + checked(slot * slotCapacity);
        var mat = new Mat(height, width, MatType.CV_8UC4);
        try
        {
            var destinationStride = checked((int)mat.Step());
            if (stride == destinationStride)
            {
                view.CopyTo(source, mat.Data, checked((int)dataLength));
            }
            else
            {
                var rowLength = checked(width * 4);
                for (var y = 0; y < height; y++)
                {
                    view.CopyTo(
                        source + checked((long)y * stride),
                        mat.Data + checked(y * destinationStride),
                        rowLength);
                }
            }

            var sequenceAfter = view.ReadUInt64(80);
            if (sequenceAfter != sequenceBefore || (sequenceAfter & 1) != 0)
                throw new CaptureRingConsistencyException(
                    "Capture ring frame changed while it was being read.");

            var desktop = desktopRegionProvider?.Invoke() ??
                new DesktopRegion(width, height);
            return new GameCaptureRegion(
                mat, captureX, captureY, desktop,
                new TranslationConverter(captureX, captureY));
        }
        catch
        {
            mat.Dispose();
            throw;
        }
    }

    private static string RequiredString(JToken token, string name) =>
        token.Value<string>(name) is { Length: > 0 } value
            ? value
            : throw new InvalidDataException($"capture.request omitted {name}.");

    private static int RequiredInt(JToken token, string name) =>
        token.Value<int?>(name) ??
        throw new InvalidDataException($"capture.request omitted {name}.");

    private static ulong RequiredUInt64(JToken token, string name) =>
        token.Value<ulong?>(name) ??
        throw new InvalidDataException($"capture.request omitted {name}.");

    [DllImport("libSystem.B.dylib", EntryPoint = "shm_open", SetLastError = true)]
    private static extern int ShmOpen(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string name,
        int oflag,
        uint mode);

    [DllImport("libSystem.B.dylib", EntryPoint = "mmap", SetLastError = true)]
    private static extern IntPtr Mmap(
        IntPtr address,
        nuint length,
        int protection,
        int flags,
        int descriptor,
        long offset);

    [DllImport("libSystem.B.dylib", EntryPoint = "munmap", SetLastError = true)]
    private static extern int Munmap(IntPtr address, nuint length);

    [DllImport("libSystem.B.dylib", EntryPoint = "memcpy")]
    private static extern IntPtr Memcpy(IntPtr destination, IntPtr source, nuint count);

    private static Regex SharedMemoryNamePattern() => SharedMemoryNameRegex;

    private static readonly Regex SharedMemoryNameRegex = new(
        "^/bettergi-mac-capture-[0-9]+-[0-9]+$",
        RegexOptions.CultureInvariant);

    private interface IReadView
    {
        byte ReadByte(long offset);
        int ReadInt32(long offset);
        uint ReadUInt32(long offset);
        ulong ReadUInt64(long offset);
        void ReadArray(long offset, byte[] destination, int index, int count);
        void CopyTo(long offset, IntPtr destination, int count);
    }

    private sealed class AccessorView(
        MemoryMappedViewAccessor accessor) : IReadView
    {
        public byte ReadByte(long offset) => accessor.ReadByte(offset);
        public int ReadInt32(long offset) => accessor.ReadInt32(offset);
        public uint ReadUInt32(long offset) => accessor.ReadUInt32(offset);
        public ulong ReadUInt64(long offset) => accessor.ReadUInt64(offset);
        public void ReadArray(
            long offset,
            byte[] destination,
            int index,
            int count) =>
            accessor.ReadArray(offset, destination, index, count);

        public void CopyTo(long offset, IntPtr destination, int count)
        {
            var buffer = new byte[count];
            accessor.ReadArray(offset, buffer, 0, count);
            Marshal.Copy(buffer, 0, destination, count);
        }
    }

    private sealed class PosixMappedView : IReadView, IDisposable
    {
        private static readonly IntPtr MapFailed = new(-1);
        private readonly nuint _length;
        private IntPtr _address;

        private PosixMappedView(IntPtr address, nuint length)
        {
            _address = address;
            _length = length;
        }

        public static PosixMappedView Open(
            int descriptor,
            long length,
            int protection,
            int flags)
        {
            if (length <= 0)
                throw new ArgumentOutOfRangeException(nameof(length));
            var address = Mmap(
                IntPtr.Zero, checked((nuint)length), protection,
                flags, descriptor, 0);
            if (address == MapFailed)
                throw new IOException(
                    "Unable to map capture shared memory: " +
                    Marshal.GetLastPInvokeErrorMessage());
            return new PosixMappedView(address, checked((nuint)length));
        }

        public byte ReadByte(long offset) =>
            Marshal.ReadByte(Address(offset, 1));

        public int ReadInt32(long offset) =>
            Marshal.ReadInt32(Address(offset, sizeof(int)));

        public uint ReadUInt32(long offset) =>
            unchecked((uint)ReadInt32(offset));

        public ulong ReadUInt64(long offset) =>
            unchecked((ulong)Marshal.ReadInt64(
                Address(offset, sizeof(long))));

        public void ReadArray(
            long offset,
            byte[] destination,
            int index,
            int count)
        {
            ArgumentNullException.ThrowIfNull(destination);
            if (index < 0 || count < 0 ||
                index > destination.Length - count)
                throw new ArgumentOutOfRangeException(nameof(index));
            Marshal.Copy(Address(offset, count), destination, index, count);
        }

        public void CopyTo(long offset, IntPtr destination, int count)
        {
            if (destination == IntPtr.Zero)
                throw new ArgumentException("Capture destination cannot be null.", nameof(destination));
            _ = Memcpy(destination, Address(offset, count), checked((nuint)count));
        }

        public void Dispose()
        {
            if (_address == IntPtr.Zero)
                return;
            _ = Munmap(_address, _length);
            _address = IntPtr.Zero;
        }

        private IntPtr Address(long offset, int count)
        {
            if (offset < 0 || count < 0 ||
                checked((nuint)offset + (nuint)count) > _length)
                throw new InvalidDataException(
                    "Capture shared-memory read exceeds the mapped view.");
            return IntPtr.Add(_address, checked((int)offset));
        }
    }
}
