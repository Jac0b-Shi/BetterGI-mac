import Foundation

enum RedeemCodeClipboardPolicy {
    private static let pattern =
        #"(?<![A-Z0-9])(?=[A-Z0-9]*[A-Z])[A-Z0-9]{12}(?![A-Z0-9])"#

    static func extractCodes(from text: String) -> [String] {
        guard !text.isEmpty, text.count <= 1_000,
              let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }
}
