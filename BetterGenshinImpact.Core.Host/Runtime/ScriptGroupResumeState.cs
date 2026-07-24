using BetterGenshinImpact.Core.Script.Group;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

internal static class ScriptGroupResumeState
{
    public static void ApplyAndConsume(RuntimeLayout layout, ScriptGroup group)
    {
        if (!File.Exists(layout.SchedulerStatePath))
            return;

        try
        {
            var state = JObject.Parse(File.ReadAllText(layout.SchedulerStatePath));
            if (!string.Equals(
                    state.Value<string>("groupName"),
                    group.Name,
                    StringComparison.Ordinal))
            {
                return;
            }

            var startIndex = group.Projects.ToList().FindIndex(project =>
                project.Index == state.Value<int?>("index") &&
                project.FolderName == state.Value<string>("folderName") &&
                project.Name == state.Value<string>("projectName"));
            if (startIndex < 0)
                return;

            for (var index = 0; index < startIndex; index++)
                group.Projects[index].SkipFlag = true;
            File.Delete(layout.SchedulerStatePath);
        }
        catch (Exception exception) when (exception is IOException or JsonException)
        {
            throw new InvalidDataException(
                "The saved scheduler start position is invalid.",
                exception);
        }
    }
}
