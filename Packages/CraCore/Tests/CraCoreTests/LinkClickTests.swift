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
}
