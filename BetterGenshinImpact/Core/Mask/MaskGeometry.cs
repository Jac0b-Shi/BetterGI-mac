#if BGI_PLATFORM_MAC
namespace BetterGenshinImpact.Core.Mask;
public readonly record struct MaskRect(double X, double Y, double Width, double Height);
public readonly record struct MaskPoint(double X, double Y);
#endif
