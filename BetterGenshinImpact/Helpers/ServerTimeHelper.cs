using System;

namespace BetterGenshinImpact.Helpers;

/// <summary>
/// 提供配置的服务器时区的当前时间
/// </summary>
public interface IServerTimeProvider
{
    /// <summary>
    /// 获取调整到服务器时区偏移量的当前时间
    /// </summary>
    /// <returns>表示当前服务器时间的 <see cref="DateTimeOffset"/></returns>
    DateTimeOffset GetServerTimeNow();
    
    /// <summary>
    /// 获取服务器时区偏移量
    /// </summary>
    /// <returns>表示服务器时区偏移量的 <see cref="TimeSpan"/></returns>
    TimeSpan GetServerTimeOffset();
}

/// <inheritdoc cref="IServerTimeProvider"/>
/// <remarks>
/// 此实现使用 <see cref="TimeProvider"/> 获取当前UTC时间，
/// 然后应用配置的服务器时区偏移量
/// </remarks>
public class ServerTimeProvider : IServerTimeProvider
{
    private readonly TimeProvider _timeProvider;
    private readonly Func<TimeSpan> _serverTimeZoneOffset;

    /// <summary>
    /// 初始化 <see cref="ServerTimeProvider"/> 类的新实例
    /// </summary>
    /// <param name="timeProvider">用于获取基准UTC时间的 <see cref="TimeProvider"/></param>
    public ServerTimeProvider(TimeProvider timeProvider, Func<TimeSpan> serverTimeZoneOffset)
    {
        _timeProvider = timeProvider;
        _serverTimeZoneOffset = serverTimeZoneOffset ?? throw new ArgumentNullException(nameof(serverTimeZoneOffset));
    }

    /// <inheritdoc/>
    public DateTimeOffset GetServerTimeNow()
    {
        var serverOffset = GetServerTimeOffset();
        return _timeProvider.GetUtcNow().ToOffset(serverOffset);
    }

    public TimeSpan GetServerTimeOffset()
    {
        return _serverTimeZoneOffset();
    }
}

/// <summary>
/// 提供静态外观以便轻松访问服务器时间
/// </summary>
public static class ServerTimeHelper
{
    private static IServerTimeProvider? _serverTimeProvider;

    /// <summary>
    /// 使用具体的 <see cref="IServerTimeProvider"/> 实现初始化静态辅助类
    /// 此方法必须在应用程序启动期间调用一次
    /// </summary>
    /// <param name="serverTimeProvider">用于检索服务器时间的提供程序</param>
    /// <exception cref="ArgumentNullException">当 <paramref name="serverTimeProvider"/> 为 null 时抛出</exception>
    public static void Initialize(IServerTimeProvider serverTimeProvider)
    {
        _serverTimeProvider = serverTimeProvider ?? throw new ArgumentNullException(nameof(serverTimeProvider));
    }

    /// <summary>
    /// 获取调整到服务器时区偏移量的当前时间
    /// </summary>
    /// <returns>表示当前服务器时间的 <see cref="DateTimeOffset"/></returns>
    /// <exception cref="InvalidOperationException">
    /// 如果尚未调用 <see cref="Initialize"/> 则抛出
    /// </exception>
    public static DateTimeOffset GetServerTimeNow()
    {
        if (_serverTimeProvider is null)
        {
            throw new InvalidOperationException(
                $"{nameof(ServerTimeHelper)} 尚未初始化。请先调用 {nameof(Initialize)}。");
        }

        return _serverTimeProvider.GetServerTimeNow();
    }
    
    /// <summary>
    /// 获取服务器时区偏移量
    /// </summary>
    /// <returns>表示服务器时区偏移量的 <see cref="TimeSpan"/></returns>
    /// <exception cref="InvalidOperationException">
    /// 如果尚未调用 <see cref="Initialize"/> 则抛出
    /// </exception>
    public static TimeSpan GetServerTimeOffset()
    {
        if (_serverTimeProvider is null)
        {
            throw new InvalidOperationException(
                $"{nameof(ServerTimeHelper)} 尚未初始化。请先调用 {nameof(Initialize)}。");
        }

        return _serverTimeProvider.GetServerTimeOffset();
    }
}
