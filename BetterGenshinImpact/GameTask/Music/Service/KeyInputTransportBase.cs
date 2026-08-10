using BetterGenshinImpact.GameTask.Music.Model;
using System;
using System.Collections.Generic;
using System.Linq;

namespace BetterGenshinImpact.GameTask.Music.Service;

public abstract class KeyInputTransportBase : IKeyInputTransport
{
    private readonly object _syncRoot = new();
    private readonly Dictionary<char, long> _pressedKeys = [];
    private long _generation;
    private long _releaseGeneration;

    public abstract MusicInputMode Mode { get; }

    public void KeyDown(char key)
    {
        KeyDown(key, expectedReleaseGeneration: null);
    }

    private void KeyDown(char key, long? expectedReleaseGeneration)
    {
        key = NormalizeKey(key);
        long generation;
        lock (_syncRoot)
        {
            if (expectedReleaseGeneration is { } expected &&
                expected != _releaseGeneration)
            {
                return;
            }
            if (_pressedKeys.ContainsKey(key))
            {
                return;
            }

            generation = ++_generation;
            _pressedKeys.Add(key, generation);
        }

        try
        {
            SendKeyDown(key);
        }
        catch
        {
            lock (_syncRoot)
            {
                if (_pressedKeys.TryGetValue(key, out var current) && current == generation)
                {
                    _pressedKeys.Remove(key);
                }
            }
            throw;
        }

        lock (_syncRoot)
        {
            if (_pressedKeys.TryGetValue(key, out var current) && current == generation)
            {
                return;
            }
        }

        // ReleaseAll may have raced with the send. Compensate after the in-flight down.
        SendKeyUp(key);
    }

    public void KeyUp(char key)
    {
        KeyUp(key, expectedReleaseGeneration: null);
    }

    private void KeyUp(char key, long? expectedReleaseGeneration)
    {
        key = NormalizeKey(key);
        lock (_syncRoot)
        {
            if (expectedReleaseGeneration is { } expected &&
                expected != _releaseGeneration)
            {
                return;
            }
            if (!_pressedKeys.Remove(key))
            {
                return;
            }

        }

        SendKeyUp(key);
    }

    public void ReleaseAll()
    {
        char[] pressedKeys;
        lock (_syncRoot)
        {
            _releaseGeneration++;
            pressedKeys = _pressedKeys.Keys.ToArray();
            _pressedKeys.Clear();
        }

        ReleasePressedKeys(pressedKeys);
    }

    public virtual void DispatchBatch(
        IReadOnlyList<PerformanceEvent> events,
        int startIndex,
        int count)
    {
        ArgumentNullException.ThrowIfNull(events);
        if (startIndex < 0 || startIndex > events.Count)
        {
            throw new ArgumentOutOfRangeException(nameof(startIndex));
        }
        if (count < 0 || count > events.Count - startIndex)
        {
            throw new ArgumentOutOfRangeException(nameof(count));
        }

        long releaseGeneration;
        lock (_syncRoot)
        {
            releaseGeneration = _releaseGeneration;
        }

        var endIndex = startIndex + count;
        for (var index = startIndex; index < endIndex; index++)
        {
            var item = events[index];
            if (item.Type == PerformanceEventType.KeyDown)
            {
                KeyDown(item.Key, releaseGeneration);
            }
            else
            {
                KeyUp(item.Key, releaseGeneration);
            }
        }
    }

    protected abstract void SendKeyDown(char key);

    protected abstract void SendKeyUp(char key);

    protected virtual void ReleasePressedKeys(IReadOnlyList<char> pressedKeys)
    {
        foreach (var key in pressedKeys)
        {
            SendKeyUp(key);
        }
    }

    private static char NormalizeKey(char key)
    {
        key = char.ToUpperInvariant(key);
        if (key is < 'A' or > 'Z')
        {
            throw new ArgumentOutOfRangeException(nameof(key), key, "不支持的原琴按键");
        }

        return key;
    }
}
