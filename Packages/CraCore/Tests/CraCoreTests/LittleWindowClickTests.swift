import CraCore
import Foundation
import Testing

/// Arc's "Open Little Arc when clicking on links with ⌥⌘ held" (LittleWindowClick).
struct LittleWindowClickTests {
    @Test(arguments: ["https://example.com/a", "http://127.0.0.1:8765/page.html", "file:///Users/me/page.html"])
    func aPageOpensInALittleWindow(_ url: String) {
        #expect(LittleWindowClick.opens(url, incognito: false, settings: AppSettings()))
    }

    /// Cra's scheme drives the app, and the rest are not pages a Little Window shows: those clicks
    /// stay what they were (a tab, or nothing).
    @Test(arguments: ["cra://action/closeTab", "javascript:alert(1)", "about:blank", "chrome://settings",
                      "mailto:a@example.com", "", "not a url"])
    func onlyPagesOpenInALittleWindow(_ url: String) {
        #expect(!LittleWindowClick.opens(url, incognito: false, settings: AppSettings()))
    }

    @Test func theSwitchTurnsItOff() {
        var settings = AppSettings()
        settings.littleWindowOnOptionCommandClick = false
        #expect(!LittleWindowClick.opens("https://example.com/", incognito: false, settings: settings))
    }

    /// Little Windows load in the normal profile, so a private page's link stays private.
    @Test func noLittleWindowFromAnIncognitoPage() {
        #expect(!LittleWindowClick.opens("https://example.com/", incognito: true, settings: AppSettings()))
    }

    /// On by default, as in Arc, also for a settings.json saved before the switch existed.
    @Test func onByDefaultAndKeptOff() throws {
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).littleWindowOnOptionCommandClick)
        let off = Data(#"{"littleWindowOnOptionCommandClick": false}"#.utf8)
        #expect(try !JSONDecoder().decode(AppSettings.self, from: off).littleWindowOnOptionCommandClick)
    }
}
