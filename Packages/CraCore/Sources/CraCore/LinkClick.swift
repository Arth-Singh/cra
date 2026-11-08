import Foundation

/// A link clicked on a WebKit page, and where it goes. Chromium decides its own pages' clicks
/// (Blink's NavigationPolicyFromEventModifiers) and hands Cra the result as a window open
/// disposition; WebKit hands over the keys and the button (WKNavigationAction), so Cra reads them
/// the way Chromium does and both engines send a click to the same place.
public struct LinkClick: Equatable, Sendable {
    public var command: Bool
    public var option: Bool
    public var shift: Bool
    public var middleButton: Bool

    public init(command: Bool, option: Bool, shift: Bool, middleButton: Bool) {
        self.command = command
        self.option = option
        self.shift = shift
        self.middleButton = middleButton
    }

    public enum Destination: Equatable, Sendable {
        /// ⌥ with ⌘ or the middle button, without ⇧: Chromium's "open in split view", a Little
        /// Window when the setting takes it (LittleWindowClick.opens), else a tab in the background.
        case littleWindow
        /// ⌘ or the middle button: a new tab, in the background unless ⇧ is down too.
        case newTab(background: Bool)
        /// Neither ⌘ nor the middle button: this page, unless Peek takes the link. ⇧ alone is
        /// Chrome's new window, a tab in front here.
        case thisPage(shift: Bool)
    }

    public var destination: Destination {
        guard command || middleButton else { return .thisPage(shift: shift) }
        return option && !shift ? .littleWindow : .newTab(background: !shift)
    }

    /// A click with a key or button that can send a link elsewhere than its page: ⌘, ⌥, ⇧ or the
    /// middle button. cra.log names where those went (BrowserManager).
    public var isModified: Bool { command || option || shift || middleButton }

    /// The keys and the button for cra.log, the keys in the menus' order: "⌥⌘-click",
    /// "⇧ middle-click", "middle-click".
    public var keys: String {
        let k = (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "")
        guard middleButton else { return k + "-click" }
        return k.isEmpty ? "middle-click" : k + " middle-click"
    }

    /// The middle button, as WKNavigationAction.buttonNumber reports it: a mask of the button, the
    /// way NSEvent.pressedMouseButtons is (left 1, right 2, middle 4), not NSEvent's buttonNumber
    /// (left 0, right 1, middle 2).
    public static func isMiddleButton(webKitButtonNumber: Int) -> Bool { webKitButtonNumber == 1 << 2 }
}
