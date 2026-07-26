import Foundation
@testable import MacGI
import Testing

@Suite("Runtime GameTask resources")
struct BGIRuntimeResourceStoreTests {
    @Test("Bundled GameTask replaces the app-owned runtime tree")
    func bundledGameTaskReplacesRuntimeTree() throws {
        let fixture = try ResourceFixture()
        defer { fixture.remove() }
        try fixture.write("current", relativePath: "source/Common/current.txt")
        try fixture.write("stale", relativePath: "runtime/GameTask/Common/stale.txt")

        try fixture.store.synchronizeBundledGameTaskResources(sourceURL: fixture.sourceURL)

        #expect(try String(contentsOf: fixture.store.rootURL
            .appendingPathComponent("GameTask/Common/current.txt"), encoding: .utf8) == "current")
        #expect(!FileManager.default.fileExists(atPath: fixture.store.rootURL
            .appendingPathComponent("GameTask/Common/stale.txt").path))
        #expect(try stagingEntries(under: fixture.store.rootURL).isEmpty)
    }

    @Test("Missing bundled GameTask fails without changing the runtime tree")
    func missingBundledGameTaskPreservesRuntimeTree() throws {
        let fixture = try ResourceFixture()
        defer { fixture.remove() }
        try fixture.write("preserved", relativePath: "runtime/GameTask/Common/existing.txt")

        #expect(throws: (any Error).self) {
            try fixture.store.synchronizeBundledGameTaskResources(
                sourceURL: fixture.rootURL.appendingPathComponent("missing", isDirectory: true)
            )
        }

        #expect(try String(contentsOf: fixture.store.rootURL
            .appendingPathComponent("GameTask/Common/existing.txt"), encoding: .utf8) == "preserved")
        #expect(try stagingEntries(under: fixture.store.rootURL).isEmpty)
    }
}

private struct ResourceFixture {
    let rootURL: URL
    let sourceURL: URL
    let store: BGIRuntimeResourceStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-runtime-resource-test-\(UUID().uuidString)", isDirectory: true)
        sourceURL = rootURL.appendingPathComponent("source", isDirectory: true)
        store = BGIRuntimeResourceStore(rootURL: rootURL.appendingPathComponent("runtime", isDirectory: true))
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
    }

    func write(_ content: String, relativePath: String) throws {
        let url = rootURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private func stagingEntries(under rootURL: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix(".GameTask.") }
}
