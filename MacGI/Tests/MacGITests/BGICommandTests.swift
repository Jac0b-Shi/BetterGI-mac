@testable import MacGI
import Testing

@Suite("Workflow commands")
struct BGICommandTests {
    @Test("Command identity remains stable across view refreshes")
    func commandIdentityRemainsStableAcrossViewRefreshes() {
        let first = BGICommand(title: "运行", symbol: "play.fill", action: {})
        let refreshed = BGICommand(title: "运行", symbol: "play.fill", action: {})

        #expect(first.id == refreshed.id)
    }
}
