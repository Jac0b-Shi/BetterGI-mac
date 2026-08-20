import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI Core music RPC")
struct BetterGICoreMusicTests {
    @Test("Decodes the Core-owned music library and playback snapshot")
    func decodesMusicState() throws {
        let state = try BetterGICoreRPCClient.decodeMusicState([
            "rootFolder": "/tmp/music",
            "folderHistory": ["/tmp/music"],
            "savedTrackFullPath": "/tmp/music/demo.json",
            "savedPositionMilliseconds": 125.0,
            "playbackMode": "Sequential",
            "profiles": [["name": "风物之诗琴", "mappingMode": "MelodicOctaveFold"]],
            "tracks": [[
                "index": 0,
                "fullPath": "/tmp/music/demo.json",
                "relativePath": "demo.json",
                "title": "Demo",
                "author": "Author",
                "instrument": "风物之诗琴",
                "description": "",
                "composer": "",
                "arranger": "",
                "format": "Keyboard",
                "formatName": "网络键谱",
                "durationMilliseconds": 1_500.0,
                "noteCount": 2,
                "playableRatio": 1.0,
                "isValid": true,
                "error": NSNull(),
                "outputProfileName": "风物之诗琴",
                "transpose": 0,
                "mappingModeOverride": NSNull(),
                "mappingMode": "MelodicOctaveFold",
                "midiTracks": [],
            ]],
            "playback": [
                "state": "Playing",
                "positionMilliseconds": 250.0,
                "durationMilliseconds": 1_500.0,
                "speed": 1.25,
                "trackName": "Demo",
                "queueIndex": 0,
            ],
        ])

        #expect(state.tracks.count == 1)
        #expect(state.tracks[0].format == "Keyboard")
        #expect(state.tracks[0].mappingMode == "MelodicOctaveFold")
        #expect(state.tracks[0].mappingModeOverride == nil)
        #expect(state.playback.state == .playing)
        #expect(state.playback.speed == 1.25)
        #expect(state.playback.queueIndex == 0)
        #expect(state.savedPositionMilliseconds == 125)
    }

    @Test("Encodes music.play parameters with custom BPM and auto instrument switch")
    func encodesPlayMusicParameters() throws {
        let withoutCustomBpm = BetterGICoreRPCClient.playMusicParameters(
            index: 3,
            speed: 1.0,
            playbackMode: .sequential,
            startPositionMilliseconds: 250,
            customBpm: nil,
            autoSwitchInstrument: false)
        #expect(withoutCustomBpm["index"] as? Int == 3)
        #expect(withoutCustomBpm["speed"] as? Double == 1.0)
        #expect(withoutCustomBpm["playbackMode"] as? String == "Sequential")
        #expect(withoutCustomBpm["startPositionMilliseconds"] as? Double == 250)
        #expect(withoutCustomBpm["autoSwitchInstrument"] as? Bool == false)
        #expect(withoutCustomBpm["customBpm"] == nil)

        let withCustomBpm = BetterGICoreRPCClient.playMusicParameters(
            index: 0,
            speed: 1.5,
            playbackMode: .singleLoop,
            startPositionMilliseconds: 0,
            customBpm: 120,
            autoSwitchInstrument: true)
        #expect(withCustomBpm["index"] as? Int == 0)
        #expect(withCustomBpm["speed"] as? Double == 1.5)
        #expect(withCustomBpm["playbackMode"] as? String == "SingleLoop")
        #expect(withCustomBpm["startPositionMilliseconds"] as? Double == 0)
        #expect(withCustomBpm["autoSwitchInstrument"] as? Bool == true)
        #expect(withCustomBpm["customBpm"] as? Double == 120)
    }

    @Test("music.play parameters round-trip through JSON encoding")
    func playMusicParametersRoundTripThroughJSON() throws {
        let parameters = BetterGICoreRPCClient.playMusicParameters(
            index: 1,
            speed: 2.0,
            playbackMode: .shuffle,
            startPositionMilliseconds: 500,
            customBpm: 240,
            autoSwitchInstrument: true)
        let data = try JSONSerialization.data(withJSONObject: parameters)
        let decoded = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(decoded["index"] as? Int == 1)
        #expect(decoded["speed"] as? Double == 2.0)
        #expect(decoded["playbackMode"] as? String == "Shuffle")
        #expect(decoded["startPositionMilliseconds"] as? Double == 500)
        #expect(decoded["customBpm"] as? Double == 240)
        #expect(decoded["autoSwitchInstrument"] as? Bool == true)
    }
}
