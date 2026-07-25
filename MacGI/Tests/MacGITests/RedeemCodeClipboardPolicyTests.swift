import Testing
@testable import MacGI

@Suite("Redeem code clipboard policy")
struct RedeemCodeClipboardPolicyTests {
    @Test("Extracts only upstream 12-character uppercase codes")
    func extractsCodes() {
        #expect(RedeemCodeClipboardPolicy.extractCodes(
            from: "兑换码：ABCD1234EFGH，另一个 1234ABCD5678"
        ) == ["ABCD1234EFGH", "1234ABCD5678"])
        #expect(RedeemCodeClipboardPolicy.extractCodes(
            from: "123456789012 lowercaseabcd ABCD1234EFGH5"
        ).isEmpty)
    }

    @Test("Ignores clipboard payloads above the upstream limit")
    func payloadLimit() {
        #expect(RedeemCodeClipboardPolicy.extractCodes(
            from: String(repeating: "A", count: 1_001)
        ).isEmpty)
    }
}
