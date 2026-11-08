import CraCore
import Foundation
import Testing

/// Arc's "Open Little Arc when clicking on links with ⌥⌘ held" (LittleWindowClick).
struct LittleWindowClickTests {
    /// Chromium 156 decides the click for its pages (Blink's NavigationPolicyFromEventModifiers):
    /// ⌥ with ⌘ or the middle button and without ⇧ is its "open in split view", which Cra gets as
    /// CEF_WOD_NEW_SPLIT_VIEW. WebKit pages must count the same clicks.
    @Test(arguments: [
        (command: true, option: true, shift: false, middle: false, counts: true),
        (command: false, option: true, shift: false, middle: true, counts: true),
        (command: true, option: false, shift: false, middle: false, counts: false),  // a background tab
        (command: false, option: true, shift: false, middle: false, counts: false),  // a download
        (command: true, option: true, shift: true, middle: false, counts: false),    // a foreground tab
        (command: false, option: false, shift: false, middle: true, counts: false),  // a background tab
        (command: false, option: false, shift: false, middle: false, counts: false),
    ])
    func whichClicksCount(_ click: (command: Bool, option: Bool, shift: Bool, middle: Bool, counts: Bool)) {
        #expect(LittleWindowClick.isOptionCommandClick(command: click.command, option: click.option,
                                                       shift: click.shift, middleButton: click.middle) == click.counts)
    }

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
