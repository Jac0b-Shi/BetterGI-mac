import Foundation

enum BetterGIMusicPlaybackMode: String, CaseIterable, Identifiable, Sendable {
    case sequential = "Sequential"
    case singleLoop = "SingleLoop"
    case shuffle = "Shuffle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequential: "顺序播放"
        case .singleLoop: "单曲循环"
        case .shuffle: "随机播放"
        }
    }
}

enum BetterGIMusicPlaybackState: String, Sendable {
    case stopped = "Stopped"
    case playing = "Playing"
    case paused = "Paused"
}

struct BetterGIMusicProfile: Equatable, Sendable, Identifiable {
    let name: String
    let mappingMode: String
    var id: String { name }
}

struct BetterGIMusicMidiTrack: Equatable, Sendable, Identifiable {
    let index: Int
    let name: String
    let noteCount: Int
    let minNoteNumber: Int
    let maxNoteNumber: Int
    let isEnabled: Bool
    let playableRatio: Double
    var id: Int { index }
}

struct BetterGIMusicTrack: Equatable, Sendable, Identifiable {
    let index: Int
    let fullPath: String
    let relativePath: String
    let title: String
    let author: String
    let instrument: String
    let description: String
    let composer: String
    let arranger: String
    let format: String
    let formatName: String
    let durationMilliseconds: Double
    let noteCount: Int
    let playableRatio: Double
    let isValid: Bool
    let error: String?
    let outputProfileName: String
    let transpose: Int
    let mappingModeOverride: String?
    let mappingMode: String
    let midiTracks: [BetterGIMusicMidiTrack]
    var id: String { fullPath }
}

struct BetterGIMusicPlaybackSnapshot: Equatable, Sendable {
    let state: BetterGIMusicPlaybackState
    let positionMilliseconds: Double
    let durationMilliseconds: Double
    let speed: Double
    let trackName: String
    let queueIndex: Int

    static let stopped = BetterGIMusicPlaybackSnapshot(
        state: .stopped,
        positionMilliseconds: 0,
        durationMilliseconds: 0,
        speed: 1,
        trackName: "",
        queueIndex: -1)
}

struct BetterGIMusicState: Equatable, Sendable {
    let rootFolder: String
    let folderHistory: [String]
    let savedTrackFullPath: String
    let savedPositionMilliseconds: Double
    let playbackMode: BetterGIMusicPlaybackMode
    let profiles: [BetterGIMusicProfile]
    let tracks: [BetterGIMusicTrack]
    let playback: BetterGIMusicPlaybackSnapshot

    static let empty = BetterGIMusicState(
        rootFolder: "",
        folderHistory: [],
        savedTrackFullPath: "",
        savedPositionMilliseconds: 0,
        playbackMode: .sequential,
        profiles: [],
        tracks: [],
        playback: .stopped)
}

extension BetterGICoreRPCClient {
    func musicState() throws -> BetterGIMusicState {
        try Self.decodeMusicState(request(method: "music.state"))
    }

    func scanMusic(rootFolder: String) throws -> BetterGIMusicState {
        try Self.decodeMusicState(request(
            method: "music.scan",
            parameters: ["rootFolder": rootFolder]))
    }

    func playMusic(
        index: Int,
        speed: Double,
        playbackMode: BetterGIMusicPlaybackMode,
        startPositionMilliseconds: Double = 0,
        customBpm: Double? = nil,
        autoSwitchInstrument: Bool = false
    ) throws -> BetterGIMusicState {
        try Self.decodeMusicState(request(
            method: "music.play",
            parameters: Self.playMusicParameters(
                index: index,
                speed: speed,
                playbackMode: playbackMode,
                startPositionMilliseconds: startPositionMilliseconds,
                customBpm: customBpm,
                autoSwitchInstrument: autoSwitchInstrument)))
    }

    static func playMusicParameters(
        index: Int,
        speed: Double,
        playbackMode: BetterGIMusicPlaybackMode,
        startPositionMilliseconds: Double,
        customBpm: Double?,
        autoSwitchInstrument: Bool
    ) -> [String: Any] {
        var parameters: [String: Any] = [
            "index": index,
            "speed": speed,
            "playbackMode": playbackMode.rawValue,
            "startPositionMilliseconds": startPositionMilliseconds,
            "autoSwitchInstrument": autoSwitchInstrument,
        ]
        if let customBpm {
            parameters["customBpm"] = customBpm
        }
        return parameters
    }

    func musicCommand(_ method: String) throws -> BetterGIMusicState {
        try Self.decodeMusicState(request(method: method))
    }

    func seekMusic(positionMilliseconds: Double) throws -> BetterGIMusicState {
        try Self.decodeMusicState(request(
            method: "music.seek",
            parameters: ["positionMilliseconds": positionMilliseconds]))
    }

    func setMusicSpeed(_ speed: Double) throws -> BetterGIMusicState {
        try Self.decodeMusicState(request(
            method: "music.setSpeed",
            parameters: ["speed": speed]))
    }

    func setMusicPlaybackMode(_ mode: BetterGIMusicPlaybackMode) throws -> BetterGIMusicState {
        try Self.decodeMusicState(request(
            method: "music.setPlaybackMode",
            parameters: ["playbackMode": mode.rawValue]))
    }

    func configureMusicTrack(
        index: Int,
        outputProfileName: String,
        transpose: Int,
        disabledTrackIndexes: [Int],
        mappingModeOverride: String?
    ) throws -> BetterGIMusicState {
        try Self.decodeMusicState(request(
            method: "music.configureTrack",
            parameters: [
                "index": index,
                "outputProfileName": outputProfileName,
                "transpose": transpose,
                "disabledTrackIndexes": disabledTrackIndexes,
                "mappingMode": mappingModeOverride ?? NSNull(),
            ]))
    }

    static func decodeMusicState(_ value: Any) throws -> BetterGIMusicState {
        let root = try object(value, "music state")
        let playbackValue = try object(root["playback"], "music playback")
        let playbackStateText = try string(playbackValue, "state")
        guard let playbackState = BetterGIMusicPlaybackState(rawValue: playbackStateText),
              let playbackMode = BetterGIMusicPlaybackMode(
                rawValue: try string(root, "playbackMode"))
        else {
            throw BetterGICoreRPCError.protocolViolation("Invalid music playback state.")
        }

        let profiles = try array(root, "profiles").map { item in
            let value = try object(item, "music profile")
            return BetterGIMusicProfile(
                name: try string(value, "name"),
                mappingMode: try string(value, "mappingMode"))
        }
        let tracks = try array(root, "tracks").map { item in
            let value = try object(item, "music track")
            let midiTracks = try array(value, "midiTracks").map { midiItem in
                let midi = try object(midiItem, "MIDI track")
                return BetterGIMusicMidiTrack(
                    index: try integer(midi, "index"),
                    name: try string(midi, "name"),
                    noteCount: try integer(midi, "noteCount"),
                    minNoteNumber: try integer(midi, "minNoteNumber"),
                    maxNoteNumber: try integer(midi, "maxNoteNumber"),
                    isEnabled: try boolean(midi, "isEnabled"),
                    playableRatio: try number(midi, "playableRatio"))
            }
            return BetterGIMusicTrack(
                index: try integer(value, "index"),
                fullPath: try string(value, "fullPath"),
                relativePath: try string(value, "relativePath"),
                title: try string(value, "title"),
                author: try string(value, "author"),
                instrument: try string(value, "instrument"),
                description: try string(value, "description"),
                composer: try string(value, "composer"),
                arranger: try string(value, "arranger"),
                format: try string(value, "format"),
                formatName: try string(value, "formatName"),
                durationMilliseconds: try number(value, "durationMilliseconds"),
                noteCount: try integer(value, "noteCount"),
                playableRatio: try number(value, "playableRatio"),
                isValid: try boolean(value, "isValid"),
                error: value["error"] as? String,
                outputProfileName: try string(value, "outputProfileName"),
                transpose: try integer(value, "transpose"),
                mappingModeOverride: value["mappingModeOverride"] as? String,
                mappingMode: try string(value, "mappingMode"),
                midiTracks: midiTracks)
        }

        return BetterGIMusicState(
            rootFolder: try string(root, "rootFolder"),
            folderHistory: try array(root, "folderHistory").map {
                guard let value = $0 as? String else {
                    throw BetterGICoreRPCError.protocolViolation(
                        "Invalid music folder history entry.")
                }
                return value
            },
            savedTrackFullPath: try string(root, "savedTrackFullPath"),
            savedPositionMilliseconds: try number(root, "savedPositionMilliseconds"),
            playbackMode: playbackMode,
            profiles: profiles,
            tracks: tracks,
            playback: BetterGIMusicPlaybackSnapshot(
                state: playbackState,
                positionMilliseconds: try number(playbackValue, "positionMilliseconds"),
                durationMilliseconds: try number(playbackValue, "durationMilliseconds"),
                speed: try number(playbackValue, "speed"),
                trackName: try string(playbackValue, "trackName"),
                queueIndex: try integer(playbackValue, "queueIndex")))
    }

    private static func object(_ value: Any?, _ name: String) throws -> [String: Any] {
        guard let value = value as? [String: Any] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid \(name).")
        }
        return value
    }

    private static func array(_ value: [String: Any], _ key: String) throws -> [Any] {
        guard let result = value[key] as? [Any] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid music \(key).")
        }
        return result
    }

    private static func string(_ value: [String: Any], _ key: String) throws -> String {
        guard let result = value[key] as? String else {
            throw BetterGICoreRPCError.protocolViolation("Invalid music \(key).")
        }
        return result
    }

    private static func number(_ value: [String: Any], _ key: String) throws -> Double {
        guard let result = value[key] as? NSNumber else {
            throw BetterGICoreRPCError.protocolViolation("Invalid music \(key).")
        }
        return result.doubleValue
    }

    private static func integer(_ value: [String: Any], _ key: String) throws -> Int {
        guard let result = value[key] as? NSNumber else {
            throw BetterGICoreRPCError.protocolViolation("Invalid music \(key).")
        }
        return result.intValue
    }

    private static func boolean(_ value: [String: Any], _ key: String) throws -> Bool {
        guard let result = value[key] as? NSNumber else {
            throw BetterGICoreRPCError.protocolViolation("Invalid music \(key).")
        }
        return result.boolValue
    }
}

extension BetterGICoreProcessSupervisor {
    func musicState() throws -> BetterGIMusicState {
        try runningClient().musicState()
    }

    func scanMusic(rootFolder: String) throws -> BetterGIMusicState {
        try runningClient().scanMusic(rootFolder: rootFolder)
    }

    func playMusic(
        index: Int,
        speed: Double,
        playbackMode: BetterGIMusicPlaybackMode,
        startPositionMilliseconds: Double = 0,
        customBpm: Double? = nil,
        autoSwitchInstrument: Bool = false
    ) throws -> BetterGIMusicState {
        try runningClient().playMusic(
            index: index,
            speed: speed,
            playbackMode: playbackMode,
            startPositionMilliseconds: startPositionMilliseconds,
            customBpm: customBpm,
            autoSwitchInstrument: autoSwitchInstrument)
    }

    func musicCommand(_ method: String) throws -> BetterGIMusicState {
        try runningClient().musicCommand(method)
    }

    func seekMusic(positionMilliseconds: Double) throws -> BetterGIMusicState {
        try runningClient().seekMusic(positionMilliseconds: positionMilliseconds)
    }

    func setMusicSpeed(_ speed: Double) throws -> BetterGIMusicState {
        try runningClient().setMusicSpeed(speed)
    }

    func setMusicPlaybackMode(_ mode: BetterGIMusicPlaybackMode) throws -> BetterGIMusicState {
        try runningClient().setMusicPlaybackMode(mode)
    }

    func configureMusicTrack(
        index: Int,
        outputProfileName: String,
        transpose: Int,
        disabledTrackIndexes: [Int],
        mappingModeOverride: String?
    ) throws -> BetterGIMusicState {
        try runningClient().configureMusicTrack(
            index: index,
            outputProfileName: outputProfileName,
            transpose: transpose,
            disabledTrackIndexes: disabledTrackIndexes,
            mappingModeOverride: mappingModeOverride)
    }
}
