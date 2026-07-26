using BetterGenshinImpact.Core.Host.Protocol;
using Newtonsoft.Json;
using System.Buffers.Binary;
using System.Net.Sockets;
using System.Text;

namespace BetterGenshinImpact.Core.Host.Transport;

public sealed class FramedJsonConnection(Socket socket) : IAsyncDisposable
{
    private const int MaxMessageBytes = 16 * 1024 * 1024;
    private readonly NetworkStream _stream = new(socket, ownsSocket: true);

    public async Task<RpcRequest?> ReadRequestAsync(CancellationToken cancellationToken)
    {
        var header = new byte[4];
        if (!await ReadExactlyOrEofAsync(header, cancellationToken)) return null;
        var length = BinaryPrimitives.ReadInt32LittleEndian(header);
        if (length <= 0 || length > MaxMessageBytes)
            throw new InvalidDataException($"Invalid RPC frame length: {length}.");
        var payload = new byte[length];
        await _stream.ReadExactlyAsync(payload, cancellationToken);
        return JsonConvert.DeserializeObject<RpcRequest>(Encoding.UTF8.GetString(payload))
            ?? throw new InvalidDataException("RPC request is empty.");
    }

    public async Task WriteResponseAsync(RpcResponse response, CancellationToken cancellationToken)
        => await WriteMessageAsync(response, cancellationToken);

    public async Task WriteRequestAsync(RpcRequest request, CancellationToken cancellationToken)
        => await WriteMessageAsync(request, cancellationToken);

    public async Task<RpcResponse?> ReadResponseAsync(CancellationToken cancellationToken)
    {
        var payload = await ReadPayloadAsync(cancellationToken);
        return payload is null
            ? null
            : JsonConvert.DeserializeObject<RpcResponse>(Encoding.UTF8.GetString(payload))
              ?? throw new InvalidDataException("RPC response is empty.");
    }

    private async Task WriteMessageAsync(object message, CancellationToken cancellationToken)
    {
        var payload = Encoding.UTF8.GetBytes(JsonConvert.SerializeObject(message));
        if (payload.Length > MaxMessageBytes)
            throw new InvalidDataException($"RPC frame exceeds {MaxMessageBytes} bytes.");
        var header = new byte[4];
        BinaryPrimitives.WriteInt32LittleEndian(header, payload.Length);
        await _stream.WriteAsync(header, cancellationToken);
        await _stream.WriteAsync(payload, cancellationToken);
        await _stream.FlushAsync(cancellationToken);
    }

    private async Task<byte[]?> ReadPayloadAsync(CancellationToken cancellationToken)
    {
        var header = new byte[4];
        if (!await ReadExactlyOrEofAsync(header, cancellationToken)) return null;
        var length = BinaryPrimitives.ReadInt32LittleEndian(header);
        if (length <= 0 || length > MaxMessageBytes)
            throw new InvalidDataException($"Invalid RPC frame length: {length}.");
        var payload = new byte[length];
        await _stream.ReadExactlyAsync(payload, cancellationToken);
        return payload;
    }

    private async Task<bool> ReadExactlyOrEofAsync(byte[] buffer, CancellationToken cancellationToken)
    {
        var offset = 0;
        while (offset < buffer.Length)
        {
            var read = await _stream.ReadAsync(buffer.AsMemory(offset), cancellationToken);
            if (read == 0) return offset == 0 ? false : throw new EndOfStreamException();
            offset += read;
        }
        return true;
    }

    public ValueTask DisposeAsync() => _stream.DisposeAsync();
}
