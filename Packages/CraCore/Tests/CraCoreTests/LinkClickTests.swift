import CraCore
import Testing

/// Where a link clicked on a WebKit page goes (LinkClick): where Chromium 156 sends the same click
/// on its pages (Blink's NavigationPolicyFromEventModifiers, the disposition CraCEF gets).
struct LinkClickTests {
    @Test(arguments: [
        // ⌥ with ⌘ or the middle button, without ⇧: Chromium's "open in split view".
        (command: true, option: true, shift: false, middle: false, goes: LinkClick.Destination.littleWindow),
        (command: false, option: true, shift: false, middle: true, goes: .littleWindow),
        (command: true, option: true, shift: false, middle: true, goes: .littleWindow),
        // ⌘ or the middle button: a background tab; with ⇧, a foreground one (⇧⌥⌘ too).
        (command: true, option: false, shift: false, middle: false, goes: .newTab(background: true)),
        (command: false, option: false, shift: false, middle: true, goes: .newTab(background: true)),
        (command: true, option: false, shift: true, middle: false, goes: .newTab(background: false)),
        (command: false, option: false, shift: true, middle: true, goes: .newTab(background: false)),
        (command: true, option: true, shift: true, middle: false, goes: .newTab(background: false)),
        // Neither: the page itself (Peek may take it); ⇧ alone is Chrome's new window.
        (command: false, option: false, shift: false, middle: false, goes: .thisPage(shift: false)),
        (command: false, option: true, shift: false, middle: false, goes: .thisPage(shift: false)),
        (command: false, option: false, shift: true, middle: false, goes: .thisPage(shift: true)),
        (command: false, option: true, shift: true, middle: false, goes: .thisPage(shift: true)),
    ])
    func whereAClickGoes(_ c: (command: Bool, option: Bool, shift: Bool, middle: Bool, goes: LinkClick.Destination)) {
        #expect(LinkClick(command: c.command, option: c.option, shift: c.shift, middleButton: c.middle).destination == c.goes)
    }

    /// cra.log's names, and which clicks it names at all: a plain click goes where the page says.
    @Test func whatTheLogSays() {
        #expect(LinkClick(command: true, option: true, shift: false, middleButton: false).keys == "⌥⌘-click")
        #expect(LinkClick(command: true, option: true, shift: true, middleButton: false).keys == "⌥⇧⌘-click")
        #expect(LinkClick(command: false, option: false, shift: false, middleButton: true).keys == "middle-click")
        #expect(LinkClick(command: false, option: true, shift: false, middleButton: true).keys == "⌥ middle-click")
        #expect(LinkClick(command: false, option: true, shift: false, middleButton: false).isModified)
        #expect(LinkClick(command: false, option: false, shift: false, middleButton: true).isModified)
        #expect(!LinkClick(command: false, option: false, shift: false, middleButton: false).isModified)
    }

    /// WKNavigationAction.buttonNumber is a mask of the button, the way NSEvent.pressedMouseButtons
    /// is: left 1, right 2, middle 4, as a WKWebView reported real clicks sent to it (8 Nov 2026).
    /// Read as NSEvent's number (middle 2), a middle-click on a WebKit page loaded the link in
    /// place, and ⌥ with the middle button opened no Little Window.
    @Test(arguments: [(number: 1, middle: false), (number: 2, middle: false), (number: 4, middle: true), (number: 0, middle: false)])
    func webKitsMiddleButton(_ button: (number: Int, middle: Bool)) {
        #expect(LinkClick.isMiddleButton(webKitButtonNumber: button.number) == button.middle)
    }
}
