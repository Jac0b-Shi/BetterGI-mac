#if !BGI_PLATFORM_MAC
using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.Core.Script.Dependence;
using Microsoft.ClearScript;

namespace BetterGenshinImpact.Core.Script.Project;

public partial class ScriptProject
{
    static ScriptProject()
    {
        ScriptProjectHost.Configure(new WindowsScriptProjectHostInitializer());
    }

    private sealed class WindowsScriptProjectHostInitializer : IScriptProjectHostInitializer
    {
        public void Initialize(IScriptEngine engine, string workDir, string[] searchPaths, object? config) =>
            EngineExtend.InitHost(engine, workDir, searchPaths, config);

        public void SetGameMetrics(int width, int height) => GlobalMethod.SetGameMetrics(width, height);
    }
}
#endif
