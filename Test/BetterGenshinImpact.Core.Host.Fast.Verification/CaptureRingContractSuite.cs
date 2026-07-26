using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.Verification.Framework;
using Microsoft.Win32.SafeHandles;
using Newtonsoft.Json.Linq;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class CaptureRingContractSuite : IVerificationSuite
{
    private const int OpenReadWrite = 0x0002;
    private const int OpenCreate = 0x0200;
    private const int OpenExclusive = 0x0800;
    private const int ProtectReadWrite = 0x03;
    private const int MapShared = 0x0001;

    public string Name => "capture-ring";

    [SupportedOSPlatform("macos")]
    public Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var root = Path.Combine(
            Path.GetTempPath(), $"bettergi-capture-ring-{Guid.NewGuid():N}");
        var layout = new RuntimeLayout(root);
        layout.EnsureCreated();
        OverlayDrawPlatform.Configure(new NoopOverlayDrawPlatform());
        var name =
            $"/bettergi-mac-capture-{GetUserId()}-{Environment.ProcessId}";
        _ = ShmUnlink(name);
        try
        {
            using var handle = CreateSharedMemory(name, 160);
            var address = Mmap(
                IntPtr.Zero, 160, ProtectReadWrite, MapShared,
                handle.DangerousGetHandle().ToInt32(), 0);
            if (address == new IntPtr(-1))
                throw new IOException(Marshal.GetLastPInvokeErrorMessage());
            try
            {
                WriteFixture(address);
            }
            finally
            {
                _ = Munmap(address, 160);
            }

            var reader = new SharedCaptureRingReader(layout);
            using var capture = reader.Read(
                JObject.FromObject(new
                {
                    ringName = name,
                    frameId = 7UL,
                    sequence = 2UL,
                    slot = 1,
                    width = 2,
                    height = 1,
                    stride = 8,
                    pixelFormat = "BGRA8",
                }));
            var pixel = capture.SrcMat.At<OpenCvSharp.Vec4b>(0, 1);
            context.Require(
                capture.Width == 2 &&
                capture.Height == 1 &&
                capture.X == 11 &&
                capture.Y == 22 &&
                pixel[0] == 4 &&
                pixel[1] == 5 &&
                pixel[2] == 6 &&
                pixel[3] == 255,
                "Core did not read the production POSIX shared-memory BGRA ring.");

            var requestCount = 0;
            using var retriedCapture = reader.ReadLatest(() =>
            {
                requestCount++;
                return JObject.FromObject(new
                {
                    ringName = name,
                    frameId = requestCount == 1 ? 6UL : 7UL,
                    sequence = 2UL,
                    slot = 1,
                    width = 2,
                    height = 1,
                    stride = 8,
                    pixelFormat = "BGRA8",
                });
            });
            context.Require(
                requestCount == 2 &&
                retriedCapture.SrcMat.At<OpenCvSharp.Vec4b>(0, 1)[0] == 4,
                "Core did not retry a transient capture-ring consistency race.");

            context.Require(
                !File.Exists(Path.Combine(layout.RunPath, "capture-ring.bin")),
                "POSIX capture transport created a disk-backed capture ring.");
            cancellationToken.ThrowIfCancellationRequested();
            return Task.CompletedTask;
        }
        finally
        {
            _ = ShmUnlink(name);
            Directory.Delete(root, recursive: true);
        }
    }

    private static SafeFileHandle CreateSharedMemory(
        string name,
        long length)
    {
        var descriptor = ShmOpen(
            name, OpenReadWrite | OpenCreate | OpenExclusive, 0x180);
        if (descriptor < 0)
            throw new IOException(Marshal.GetLastPInvokeErrorMessage());
        var handle = new SafeFileHandle(
            (IntPtr)descriptor, ownsHandle: true);
        if (Ftruncate(descriptor, length) == 0)
            return handle;
        var message = Marshal.GetLastPInvokeErrorMessage();
        handle.Dispose();
        throw new IOException(message);
    }

    private static void WriteFixture(IntPtr address)
    {
        Marshal.Copy("BGIRING1"u8.ToArray(), 0, address, 8);
        Marshal.WriteInt32(address, 8, 1);
        Marshal.WriteInt32(address, 12, 2);
        Marshal.WriteInt64(address, 16, 16);
        Marshal.WriteInt32(address, 24, 1);
        Marshal.WriteInt32(address, 28, 2);
        Marshal.WriteInt32(address, 32, 1);
        Marshal.WriteInt32(address, 36, 8);
        Marshal.WriteInt32(address, 40, unchecked((int)0x42475241u));
        Marshal.WriteInt64(address, 48, 8);
        Marshal.WriteInt64(address, 56, 7);
        Marshal.WriteInt32(address, 64, 11);
        Marshal.WriteInt32(address, 68, 22);
        Marshal.WriteInt32(address, 72, 2);
        Marshal.WriteInt32(address, 76, 1);
        Marshal.WriteInt64(address, 80, 2);
        Marshal.Copy(
            new byte[] { 1, 2, 3, 255, 4, 5, 6, 255 },
            0,
            IntPtr.Add(address, 128 + 16),
            8);
    }

    [DllImport(
        "libSystem.B.dylib",
        EntryPoint = "shm_open",
        SetLastError = true)]
    private static extern int ShmOpen(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string name,
        int flags,
        uint mode);

    [DllImport(
        "libSystem.B.dylib",
        EntryPoint = "shm_unlink",
        SetLastError = true)]
    private static extern int ShmUnlink(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string name);

    [DllImport(
        "libSystem.B.dylib",
        EntryPoint = "ftruncate",
        SetLastError = true)]
    private static extern int Ftruncate(int descriptor, long length);

    [DllImport(
        "libSystem.B.dylib",
        EntryPoint = "mmap",
        SetLastError = true)]
    private static extern IntPtr Mmap(
        IntPtr address,
        nuint length,
        int protection,
        int flags,
        int descriptor,
        long offset);

    [DllImport(
        "libSystem.B.dylib",
        EntryPoint = "munmap",
        SetLastError = true)]
    private static extern int Munmap(IntPtr address, nuint length);

    [DllImport("libSystem.B.dylib", EntryPoint = "getuid")]
    private static extern uint GetUserId();

    private sealed class NoopOverlayDrawPlatform : IOverlayDrawPlatform
    {
        public void SetRectangles(
            string name,
            Region source,
            IReadOnlyList<OpenCvSharp.Rect> rectangles)
        {
        }

        public void RemoveRectangles(string name)
        {
        }

        public void ClearAll()
        {
        }
    }
}
