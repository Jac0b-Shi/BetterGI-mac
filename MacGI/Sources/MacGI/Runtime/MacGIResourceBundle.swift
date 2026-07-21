import Foundation

extension Bundle {
    static nonisolated let macGIResources: Bundle = {
        if let url = Bundle.main.url(
            forResource: "betterGI-mac_MacGI",
            withExtension: "bundle"
        ), let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()
}
