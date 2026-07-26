using Microsoft.ClearScript.V8;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Host.Runtime;

public static class NativeDependencySmoke
{
    public static NativeDependencyStatus Run()
    {
        using var engine = new V8ScriptEngine();
        var clearScriptResult = engine.Evaluate("40 + 2");
        if (Convert.ToInt32(clearScriptResult) != 42)
            throw new InvalidOperationException("ClearScript V8 returned an unexpected result.");
        var openCvVersion = Cv2.GetVersionString();
        if (string.IsNullOrWhiteSpace(openCvVersion))
            throw new InvalidOperationException("OpenCV returned an empty version.");
        return new NativeDependencyStatus(
            Environment.Version.ToString(),
            System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString(),
            openCvVersion,
            true);
    }
}

public sealed record NativeDependencyStatus(
    string RuntimeVersion,
    string Architecture,
    string OpenCvVersion,
    bool ClearScriptReady);
