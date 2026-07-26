using OpenCvSharp;

namespace Fischless.GameCapture.BitBlt;

/// <summary>
/// Bridges BitBlt-owned pooled memory into OpenCvSharp without depending on
/// OpenCvSharp's private native-pointer constructor. OpenCvSharp 4.13 made that
/// pointer immutable, so a Mat cannot safely own the pool-return callback.
/// Clone before returning and release the borrowed buffer immediately.
/// </summary>
public static class BitBltMat
{
    public static Mat FromPixelData(BitBltSession session, int rows, int cols, MatType type, IntPtr data, long step = 0)
    {
        if (data == IntPtr.Zero)
            throw new OpenCvSharpException("Pixel data address is NULL");

        try
        {
            using var borrowed = Mat.FromPixelData(rows, cols, type, data, step);
            return borrowed.Clone();
        }
        finally
        {
            session.ReleaseBuffer(data);
        }
    }
}
