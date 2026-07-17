import CoreGraphics
import Foundation

// MARK: - Command Model

struct BGICombatCommand: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case elementalSkill, elementalBurst, normalAttack
        case walk(seconds: Double), wait(seconds: Double)
        case switchCharacter(waitSeconds: Double), holdSkill, jump, dash
        case charge(seconds: Double?)
        case walkDirection(dir: String, seconds: Double)
        case mouseDown(String?), mouseUp(String?), click(String?)
        case keyPress(String), keyDown(String), keyUp(String)
        case scroll(clicks: Int)
        case moveBy(x: Int, y: Int)
        case ready, roundMarker
    }
    let kind: Kind
}

struct BGIAutoFightStrategy: Sendable {
    let name: String
    var commands: [BGICombatCommand]
    init(name: String, text: String) {
        self.name = name
        self.commands = BGIAutoFightParser.parse(text)
    }
}

enum BGIAutoFightParser {
    static func parse(_ text: String) -> [BGICombatCommand] {
        let normalized = text.replacing("\r\n", with: "\n").replacing("\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
            .filter { let t = $0.trimmingCharacters(in: .whitespaces)
                .replacing("（", with: "(").replacing("）", with: ")").replacing("，", with: ",")
                return !t.isEmpty && !t.hasPrefix("//") && !t.hasPrefix("#") }
        var commands: [BGICombatCommand] = []
        for line in lines {
            let tokens = line.replacing("（", with: "(").replacing("）", with: ")").replacing("，", with: ",")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for token in tokens where !token.contains(" ") {
                if let cmd = parseToken(token) { commands.append(cmd) }
            }
        }
        return commands
    }

    private static func parseToken(_ token: String) -> BGICombatCommand? {
        let lower = token.lowercased()
        let val = extractValue(from: lower)
        let vals = extractTwoValues(from: lower)
        let kind: BGICombatCommand.Kind? = {
            if lower.hasPrefix("e(hold)") { return .holdSkill }
            if lower.hasPrefix("e") || lower == "skill" { return .elementalSkill }
            if lower.hasPrefix("q") || lower == "burst" { return .elementalBurst }
            if lower.hasPrefix("attack") { return .normalAttack }
            if lower.hasPrefix("charge") { return .charge(seconds: val) }
            if lower.hasPrefix("jump") { return .jump }
            if lower.hasPrefix("dash") { return .dash }
            if lower.hasPrefix("ready") { return .ready }
            if lower.hasPrefix("round") { return .roundMarker }
            if lower.hasPrefix("wait") { return .wait(seconds: val ?? 1.0) }
            if lower.hasPrefix("s") && val != nil { return .switchCharacter(waitSeconds: val!) }
            if lower.hasPrefix("s") { return .switchCharacter(waitSeconds: 0) }
            if lower.hasPrefix("w(") { return .walk(seconds: val ?? 0.5) }
            if lower.hasPrefix("a(") { return .walkDirection(dir: "a", seconds: val ?? 0.5) }
            if lower.hasPrefix("d(") { return .walkDirection(dir: "d", seconds: val ?? 0.5) }
            if lower.hasPrefix("walk(") && vals != nil { return .walkDirection(dir: vals!.0, seconds: vals!.1) }
            if lower.hasPrefix("scroll") { return .scroll(clicks: Int(val ?? 0)) }
            if lower.hasPrefix("keydown") { return .keyDown(lower.dropFirst(8).dropLast().trimmed) }
            if lower.hasPrefix("keyup") { return .keyUp(lower.dropFirst(6).dropLast().trimmed) }
            if lower.hasPrefix("keypress") { return .keyPress(lower.dropFirst(9).dropLast().trimmed) }
            if lower.hasPrefix("mousedown") { return .mouseDown(val.flatMap { String($0) }) }
            if lower.hasPrefix("mouseup") { return .mouseUp(val.flatMap { String($0) }) }
            if lower.hasPrefix("click") { return .click(val.flatMap { String($0) }) }
            if lower.hasPrefix("moveby") && vals != nil { return .moveBy(x: Int(vals!.0) ?? 0, y: Int(vals!.1) ?? 0) }
            return nil
        }()
        return kind.map { BGICombatCommand(kind: $0) }
    }

    private static func extractValue(from token: String) -> Double? {
        guard let s = token.firstIndex(of: "("), let e = token.lastIndex(of: ")"), s < e else { return nil }
        return Double(token[token.index(after: s)..<e])
    }

    private static func extractTwoValues(from token: String) -> (String, Double)? {
        guard let s = token.firstIndex(of: "("), let e = token.lastIndex(of: ")"), s < e else { return nil }
        let inner = token[token.index(after: s)..<e]
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, let sec = Double(parts[1]) else { return nil }
        return (String(parts[0]), sec)
    }
}

private extension Substring {
    var trimmed: String { trimmingCharacters(in: CharacterSet(charactersIn: "()")) }
}

struct BGIAutoFightConfig: Sendable {
    var tickIntervalMs: Int = 100
    var defaultAttackDuration: Double = 1.5
    var cooldownBetweenCommandsMs: Int = 50
    static let `default` = BGIAutoFightConfig()
}

// MARK: - Combat Avatar Database

struct BGICombatAvatar: Codable, Sendable {
    let alias: [String]
    let id: String
    let name: String
    let nameEn: String?
    let weapon: String?
}

enum BGICombatAvatarDB {
    private static let shared: [BGICombatAvatar] = {
        guard let url = Bundle.module.url(
            forResource: "combat_avatar",
            withExtension: "json",
            subdirectory: "Resources/GameTask/AutoFight/Config"
        ) else { return [] }
        return (try? JSONDecoder().decode([BGICombatAvatar].self, from: Data(contentsOf: url))) ?? []
    }()

    static func find(named name: String) -> BGICombatAvatar? {
        shared.first { $0.alias.contains(name) || $0.name == name || $0.nameEn == name }
    }

    static var all: [BGICombatAvatar] { shared }
}

// MARK: - Service

final class BGIAutoFightService: @unchecked Sendable {
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult

    private let inputHandler: InputHandler
    private let keyBindings: KeyBindingsConfig
    private let config: BGIAutoFightConfig
    private let monsterPipeline: BGIYOLODetectionPipeline?

    init(
        inputHandler: @escaping InputHandler,
        keyBindings: KeyBindingsConfig = .bgiDefault,
        monsterPipeline: BGIYOLODetectionPipeline? = nil,
        config: BGIAutoFightConfig = .default
    ) {
        self.inputHandler = inputHandler
        self.keyBindings = keyBindings
        self.monsterPipeline = monsterPipeline
        self.config = config
    }

    func executeStrategy(_ strategy: BGIAutoFightStrategy) async {
        for cmd in strategy.commands {
            guard !Task.isCancelled else { break }
            await execute(cmd)
            try? await Task.sleep(nanoseconds: UInt64(config.cooldownBetweenCommandsMs) * 1_000_000)
        }
    }

    func executeFile(_ path: String) async throws {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let strategy = BGIAutoFightStrategy(name: URL(fileURLWithPath: path).lastPathComponent, text: text)
        await executeStrategy(strategy)
    }

    /// Detect visible monsters in the captured frame using YOLO.
    /// Returns count of detected monsters (0 if pipeline unavailable or none found).
    func detectMonsters(in image: CGImage) -> Int {
        guard let pipeline = monsterPipeline else { return 0 }
        guard let result = try? pipeline.detect(image: image) else { return 0 }
        return result.detections.count
    }

    /// Convenience: create a YOLO-based monster detection pipeline for BgiWorld model.
    static func makeWorldMonsterPipeline() -> BGIYOLODetectionPipeline? {
        guard let runtime = try? BGIYOLORuntime() else { return nil }
        guard let session = try? runtime.makeSession(model: .bgiWorld) else { return nil }
        return BGIYOLODetectionPipeline(
            session: session,
            labels: BGIOnnxModel.bgiWorld.defaultYOLOLabels
        )
    }

    private func execute(_ cmd: BGICombatCommand) async {
        switch cmd.kind {
        case .elementalSkill: await act(.elementalSkill)
        case .elementalBurst: await act(.elementalBurst)
        case .normalAttack, .charge: await act(.normalAttack)
        case .walk(let s): await hold(.moveForward, for: s)
        case .wait(let s):
            try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
        case .switchCharacter(let s):
            if s > 0 { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
        case .holdSkill: await hold(.elementalSkill, for: 1.5)
        case .jump: await act(.jump)
        case .dash: await act(.sprintMouse)
        case .walkDirection: break // pending directional walk implementation
        case .scroll(let clicks):
            _ = await inputHandler(.verticalScroll(clicks: clicks))
        case .keyDown, .keyUp, .keyPress: break // pending keyboard macro support
        case .mouseDown, .mouseUp, .click: break // pending mouse macro support
        case .moveBy: break // pending
        case .ready, .roundMarker: break
        }
    }

    private func act(_ action: GIAction) async {
        guard let ia = keyBindings.inputAction(for: action, type: .keyPress) else { return }
        _ = await inputHandler(ia)
    }

    private func hold(_ action: GIAction, for seconds: Double) async {
        guard let down = keyBindings.inputAction(for: action, type: .keyDown) else { return }
        _ = await inputHandler(down)
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        if let up = keyBindings.inputAction(for: action, type: .keyUp) {
            _ = await inputHandler(up)
        }
    }
}
