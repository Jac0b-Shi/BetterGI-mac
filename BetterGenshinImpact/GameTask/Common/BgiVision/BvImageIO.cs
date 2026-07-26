using System.IO;
using OpenCvSharp;

namespace BetterGenshinImpact.GameTask.Common.BgiVision;

public static partial class Bv
{
    /// <summary>Reads image bytes through a stream so Unicode paths work consistently.</summary>
    public static Mat ImRead(string fileName, ImreadModes flags = ImreadModes.Color) =>
        Mat.FromStream(File.OpenRead(fileName), flags);
}
