using OpenCvSharp;

namespace BetterGenshinImpact.Core.Recognition.OpenCv;

public class ArithmeticHelper
{
    /// <summary>
    ///     水平投影
    /// </summary>
    /// <param name="gray"></param>
    /// <returns></returns>
    public static int[] HorizontalProjection(Mat gray)
    {
        var height = gray.Height;
        var width = gray.Width;
        var projection = new int[height];
        //对每一行计算投影值
        for (var y = 0; y < height; ++y)
            //遍历这一行的每一个像素，如果是有效的，累加投影值
            for (var x = 0; x < width; ++x)
            {
                var s = gray.Get<Vec2b>(y, x);
                if (s.Item0 == 255) projection[y]++;
            }

        return projection;
    }

    /// <summary>
    ///     垂直投影
    /// </summary>
    /// <param name="gray"></param>
    /// <returns></returns>
    public static int[] VerticalProjection(Mat gray)
    {
        var height = gray.Height;
        var width = gray.Width;
        var projection = new int[width];
        //遍历每一列计算投影值
        for (var x = 0; x < width; ++x)
            for (var y = 0; y < height; ++y)
            {
                var s = gray.Get<Vec2b>(y, x);
                if (s.Item0 == 255) projection[x]++;
            }

        return projection;
    }
}
