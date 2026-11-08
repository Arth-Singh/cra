import Foundation

/// Arc grows a Little Window from the pointer to its frame in about 120 ms. Cra runs the grow
/// without blocking the main thread: NSWindow.setFrame(animate: true) stopped Chromium's UI
/// thread, and so the page, for the whole grow (scripts/lint.py blocking-frame-animation). Other
/// work now runs while the window grows: the page window arrives, the window closes, the page
/// moves to a space, show() comes again. This decides what each of those does.
public struct LittleWindowGrow: Equatable, Sendable {
    /// How a grow ends: its animation finished, the window closed, or the page moved to a space.
    public enum End: Sendable {
        case finished, closed, promoting
    }

    /// What ending a grow does.
    public struct Steps: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// The content's frozen size goes and the window lays out at its size.
        public static let layout = Steps(rawValue: 1 << 0)
        /// The page window, transparent while the window grew (it would stick out of the growing
        /// frame), is shown again.
        public static let showPage = Steps(rawValue: 1 << 1)
        /// The page (or the command bar) takes the keyboard.
        public static let focus = Steps(rawValue: 1 << 2)
    }

    public private(set) var generation = 0
    public private(set) var isGrowing = false

    public init() {}

    /// show() starts a grow, and gets its generation for the animation's completion. A second
    /// show() while the window grows gets nil and leaves that grow alone.
    public mutating func start() -> Int? {
        guard !isGrowing else { return nil }
        generation += 1
        isGrowing = true
        return generation
    }

    /// Ends the grow `generation` started. A completion that comes after the grow already ended
    /// (closed, promoted) or for an earlier grow does nothing.
    /// - finished: everything, as at the end of the old blocking grow, except the keyboard when
    ///   another of Cra's windows took it while the window grew (`keyElsewhere`: a popup opened in
    ///   the background hands it back to its opener right after show()).
    /// - promoting: the page goes on in a browser window, so its window must be shown; the keyboard
    ///   goes with the page, not to this window.
    /// - closed: the window and its page are gone.
    public mutating func end(_ how: End, generation: Int, keyElsewhere: Bool = false) -> Steps {
        guard isGrowing, generation == self.generation else { return [] }
        isGrowing = false
        switch how {
        case .finished: return keyElsewhere ? [.layout, .showPage] : [.layout, .showPage, .focus]
        case .promoting: return [.layout, .showPage]
        case .closed: return []
        }
    }

    /// A page window that arrives while the window grows stays transparent until the grow ends.
    public var hidesNewPageWindow: Bool { isGrowing }
}
