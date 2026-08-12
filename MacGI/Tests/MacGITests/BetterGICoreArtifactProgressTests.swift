import Testing
@testable import MacGI

@Suite("BetterGI Core artifact progress")
struct BetterGICoreArtifactProgressTests {
    @Test("Parses structured Core download progress")
    func parsesStructuredProgress() {
        let line = BetterGICoreArtifactProgress.outputPrefix
            + #"{"phase":"downloading","sourceId":"map","displayName":"地图资源 1.0.21","bytesCompleted":5242880,"bytesTotal":10485760,"sourceIndex":1,"sourceCount":1}"#

        let progress = BetterGICoreArtifactProgress.parse(outputLine: line)

        #expect(progress?.phase == "downloading")
        #expect(progress?.displayName == "地图资源 1.0.21")
        #expect(progress?.fractionCompleted == 0.5)
        #expect(progress?.sourceIndex == 1)
        #expect(progress?.sourceCount == 1)
    }

    @Test("Ignores normal Core output")
    func ignoresNormalOutput() {
        #expect(BetterGICoreArtifactProgress.parse(outputLine: "Core initialized") == nil)
    }
}
