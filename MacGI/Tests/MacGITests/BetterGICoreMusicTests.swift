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
}
