using System.Runtime.InteropServices;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.GameTask.AutoSkip;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacProcessAudioSampleCapture : IAutoSkipAudioSampleCapture
{
    private readonly PlatformCallbackChannel _callbacks;
    private readonly string _sessionToken;
    private readonly CancellationToken _cancellationToken;
    private bool _disposed;

    public MacProcessAudioSampleCapture(
        int processId,
        PlatformCallbackChannel callbacks,
        string sessionToken,
        CancellationToken cancellationToken)
    {
        _callbacks = callbacks;
        _sessionToken = sessionToken;
        _cancellationToken = cancellationToken;
        RequireAcknowledgement("audio.start", JObject.FromObject(new
        {
            processId,
            sampleRate = 16000,
            channels = 1,
            sampleFormat = "float32le"
        }));
    }

    public void ReadAvailableSamples(List<float> destination)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var response = Invoke("audio.read", null);
        if (response.Value<string>("sampleFormat") != "float32le")
            throw new InvalidDataException("audio.read returned an unsupported sample format.");
        var encoded = response.Value<string>("samplesBase64")
            ?? throw new InvalidDataException("audio.read did not return samplesBase64.");
        var bytes = Convert.FromBase64String(encoded);
        if (bytes.Length % sizeof(float) != 0)
            throw new InvalidDataException("audio.read returned a partial float32 sample.");
        var count = bytes.Length / sizeof(float);
        if (response.Value<int?>("sampleCount") != count)
            throw new InvalidDataException("audio.read sampleCount does not match its payload.");
        var samples = MemoryMarshal.Cast<byte, float>(bytes);
        for (var index = 0; index < samples.Length; index++)
            destination.Add(samples[index]);
    }

    public void DiscardAvailableSamples()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        RequireAcknowledgement("audio.discard", null);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        RequireAcknowledgement("audio.stop", null);
    }

    private JToken Invoke(string method, JObject? parameters) => _callbacks.InvokeAsync(
            method, parameters, _sessionToken, _cancellationToken).GetAwaiter().GetResult()
        ?? throw new InvalidDataException($"{method} returned an empty response.");

    private void RequireAcknowledgement(string method, JObject? parameters)
    {
        if (Invoke(method, parameters).Value<bool?>("acknowledged") != true)
            throw new InvalidDataException($"{method} did not return acknowledged=true.");
    }
}
