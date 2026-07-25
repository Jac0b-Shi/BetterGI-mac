using BetterGenshinImpact.Core.Host.Protocol;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Transport;

/// <summary>
/// Authenticated reverse-RPC channel owned by the Swift process. Calls are serialized so
/// each response is paired with the request currently on the wire; no polling or fallback.
/// </summary>
public sealed class PlatformCallbackChannel
{
    private readonly SemaphoreSlim _callLock = new(1, 1);
    private readonly object _stateLock = new();
    private FramedJsonConnection? _connection;
    private TaskCompletionSource _detached = NewDetachedSource();

    public bool IsAttached
    {
        get { lock (_stateLock) return _connection is not null; }
    }

    public Task AttachAsync(FramedJsonConnection connection, CancellationToken cancellationToken)
    {
        Task detachedTask;
        lock (_stateLock)
        {
            if (_connection is not null)
                throw new InvalidOperationException("A platform callback channel is already attached.");
            _connection = connection;
            _detached = NewDetachedSource();
            detachedTask = _detached.Task;
        }
        return detachedTask.WaitAsync(cancellationToken);
    }

    public async Task<JToken?> InvokeAsync(string method, JObject? parameters, string sessionToken,
        CancellationToken cancellationToken)
    {
        await _callLock.WaitAsync(cancellationToken);
        try
        {
            FramedJsonConnection connection;
            lock (_stateLock)
                connection = _connection ?? throw new InvalidOperationException("Swift platform callback channel is not attached.");

            var id = "platform-" + Guid.NewGuid().ToString("N");
            try
            {
                cancellationToken.ThrowIfCancellationRequested();

                // Once a request is on the shared callback stream, its response must be
                // drained before cancellation can be observed or the framing is lost.
                await connection.WriteRequestAsync(
                    new RpcRequest(id, method, parameters, sessionToken),
                    CancellationToken.None);
                var response = await connection.ReadResponseAsync(CancellationToken.None)
                    ?? throw new EndOfStreamException("Swift disconnected before acknowledging the platform callback.");
                if (!string.Equals(response.Id, id, StringComparison.Ordinal))
                    throw new InvalidDataException($"Platform callback response id '{response.Id}' does not match '{id}'.");
                cancellationToken.ThrowIfCancellationRequested();
                if (response.Error is not null)
                    throw new PlatformCallbackException(response.Error.Code, response.Error.Message);
                return response.Result is null ? null : JToken.FromObject(response.Result);
            }
            catch (PlatformCallbackException)
            {
                throw;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch
            {
                Detach(connection);
                throw;
            }
        }
        finally
        {
            _callLock.Release();
        }
    }

    public void Detach(FramedJsonConnection connection)
    {
        lock (_stateLock)
        {
            if (!ReferenceEquals(_connection, connection)) return;
            _connection = null;
            _detached.TrySetResult();
        }
    }

    private static TaskCompletionSource NewDetachedSource() =>
        new(TaskCreationOptions.RunContinuationsAsynchronously);
}

public sealed class PlatformCallbackException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}
