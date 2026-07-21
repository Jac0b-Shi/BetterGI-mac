import CoreText
import Foundation

@MainActor
enum FontRegistry {
    private static var didRegister = false

    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true

        for name in ["Fgi-Regular", "MiSans-Regular"] {
            guard let url = Bundle.macGIResources.url(forResource: name, withExtension: "ttf") else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
