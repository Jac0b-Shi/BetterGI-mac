#if BGI_PLATFORM_MAC
using System.Drawing;
using System.Globalization;
namespace BetterGenshinImpact.Core.Mask;
public static class MaskColorHelper
{
    public static Color? ParseRgbaHexColor(string? value)
    {
        var hex = value?.Trim().TrimStart('#');
        if (hex is null || (hex.Length != 6 && hex.Length != 8) ||
            !uint.TryParse(hex, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out _)) return null;
        byte Part(int offset) => byte.Parse(hex.Substring(offset, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        return Color.FromArgb(hex.Length == 8 ? Part(6) : 255, Part(0), Part(2), Part(4));
    }
}
#endif
