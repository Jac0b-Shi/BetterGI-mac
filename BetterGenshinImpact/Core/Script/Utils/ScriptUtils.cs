using System;
using System.IO;
using System.Linq;

namespace BetterGenshinImpact.Core.Script.Utils;

public class ScriptUtils
{
    public static string GetScriptRelativePath(string root, string path)
    {
        return Path.GetRelativePath(root, path)
            .Replace('/', '\\');
    }

    /// <summary>
    /// Normalize and validate a path.
    /// </summary>
    public static string NormalizePath(string root, string path)
    {
        if (string.IsNullOrWhiteSpace(path))
            throw new ArgumentException("文件路径不能为空");

        var normalizedPath = path
            .Replace('\\', Path.DirectorySeparatorChar)
            .Replace('/', Path.DirectorySeparatorChar);
        if (Path.IsPathFullyQualified(normalizedPath) ||
            HasWindowsDrivePrefix(path) ||
            path.StartsWith(@"\\", StringComparison.Ordinal) ||
            path.StartsWith("//", StringComparison.Ordinal))
        {
            throw new ArgumentException($"文件路径 '{path}' 必须是相对于脚本目录的路径");
        }

        var invalidChars = Path.GetInvalidFileNameChars();
        string fileName = Path.GetFileName(normalizedPath);
        if (fileName.Any(c => invalidChars.Contains(c)))
            throw new ArgumentException($"文件路径 '{path}' 包含非法字符");

        var normalizedRoot = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root));
        var fullPath = Path.GetFullPath(Path.Combine(normalizedRoot, normalizedPath));
        var comparison = OperatingSystem.IsWindows()
            ? StringComparison.OrdinalIgnoreCase
            : StringComparison.Ordinal;
        if (!string.Equals(fullPath, normalizedRoot, comparison) &&
            !fullPath.StartsWith(
                normalizedRoot + Path.DirectorySeparatorChar,
                comparison))
            throw new ArgumentException($"文件路径 '{path}' 越界访问!");

        return fullPath;
    }

    private static bool HasWindowsDrivePrefix(string path)
    {
        return path.Length >= 2 &&
               char.IsAsciiLetter(path[0]) &&
               path[1] == ':';
    }
}
