using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Service.Interface;
using BetterGenshinImpact.View.Windows;
using OpenCvSharp;
using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using Application = System.Windows.Application;

namespace BetterGenshinImpact.Service;

public class ConfigService : IConfigService
{
    private readonly object _locker = new(); // 只有UI线程会调用这个方法，lock好像意义不大，而且浪费了下面的读写锁hhh
    private readonly ReaderWriterLockSlim _rwLock = new();
    private const string ConfigRelativePath = @"User/config.json";
    private const string BackupFolderName = "backup";

    public static readonly JsonSerializerOptions JsonOptions = ConfigJson.Options;

    /// <summary>
    /// 写入只有UI线程会调用
    /// 多线程只会读，放心用static，不会丢失数据
    /// </summary>
    public static AllConfig? Config { get; private set; }

    public AllConfig Get()
    {
        lock (_locker)
        {
            if (Config == null)
            {
                Config = Read();
                Config.OnAnyChangedAction = Save; // 略微影响性能
                Config.InitEvent();
            }

            return Config;
        }
    }

    public void Save()
    {
        if (Config != null)
        {
            Write(Config);
        }
    }

    public AllConfig Read()
    {
        _rwLock.EnterReadLock();
        var filePath = Global.Absolute(ConfigRelativePath);
        try
        {
            if (!File.Exists(filePath))
            {
                return new AllConfig();
            }

            var json = File.ReadAllText(filePath);
            var config = JsonSerializer.Deserialize<AllConfig>(json, JsonOptions);
            if (config == null)
            {
                return new AllConfig();
            }

            Config = config;
            return config;
        }
        catch (Exception e)
        {
            Console.WriteLine(e.Message);
            Console.WriteLine(e.StackTrace);
            BackupConfigFile(filePath);
            ShowConfigExceptionDialog("读取", e);
            return new AllConfig();
        }
        finally
        {
            _rwLock.ExitReadLock();
        }
    }

    public void Write(AllConfig config)
    {
        _rwLock.EnterWriteLock();
        var file = Global.Absolute(ConfigRelativePath);
        try
        {
            var path = Global.Absolute("User");
            if (!Directory.Exists(path))
            {
                Directory.CreateDirectory(path);
            }

            File.WriteAllText(file, JsonSerializer.Serialize(config, JsonOptions));
        }
        catch (Exception e)
        {
            Console.WriteLine(e.Message);
            Console.WriteLine(e.StackTrace);
            ShowConfigExceptionDialog("写入", e);
        }
        finally
        {
            _rwLock.ExitWriteLock();
        }
    }

    private static void BackupConfigFile(string filePath)
    {
        try
        {
            if (!File.Exists(filePath))
            {
                return;
            }

            var directoryPath = Path.GetDirectoryName(filePath);
            if (string.IsNullOrWhiteSpace(directoryPath))
            {
                return;
            }

            var backupDirectory = Path.Combine(directoryPath, BackupFolderName);
            Directory.CreateDirectory(backupDirectory);

            var backupFileName = $"config_{DateTime.Now:yyyyMMdd_HHmmss_fff}.json.bak";
            var backupFilePath = Path.Combine(backupDirectory, backupFileName);
            File.Copy(filePath, backupFilePath, false);
        }
        catch (Exception ex)
        {
            Console.WriteLine(ex.Message);
            Console.WriteLine(ex.StackTrace);
        }
    }

    private static void ShowConfigExceptionDialog(string operation, Exception exception)
    {
        var current = Application.Current;
        if (current?.Dispatcher == null)
        {
            return;
        }

        var coreException = exception.GetBaseException();
        var coreStack = string.IsNullOrWhiteSpace(coreException.StackTrace) ? "无可用堆栈信息" : coreException.StackTrace;
        var message = $"配置文件{operation}失败\n错误：{coreException.Message}\n堆栈：\n{coreStack}";
        _ = ThemedMessageBox.ErrorAsync(message, "配置文件异常");
    }
}
