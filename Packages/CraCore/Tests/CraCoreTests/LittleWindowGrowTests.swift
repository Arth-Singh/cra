import CraCore
import Testing

/// features.md #2b: a Little Window grows without blocking the main thread, so a close, a move to
/// a space or a second show() can come while it grows.
struct LittleWindowGrowTests {
    enum Call: Sendable { case start, end(LittleWindowGrow.End, generation: Int, keyElsewhere: Bool = false) }
    enum Result: Equatable, Sendable { case started(Int?), steps(LittleWindowGrow.Steps) }

    static let all: LittleWindowGrow.Steps = [.layout, .showPage, .focus]

    @Test(arguments: [
        // The animation finishes: everything the blocking grow did after it.
        ([Call.start, .end(.finished, generation: 1)], [Result.started(1), .steps(all)]),
        // Closed while it grows: nothing, and the late completion does nothing either.
        ([.start, .end(.closed, generation: 1), .end(.finished, generation: 1)], [.started(1), .steps([]), .steps([])]),
        // Moved to a space while it grows: the page window shows in its new home, the keyboard
        // isn't taken here, and the late completion does nothing.
        ([.start, .end(.promoting, generation: 1), .end(.finished, generation: 1)],
         [.started(1), .steps([.layout, .showPage]), .steps([])]),
        // A second show() while it grows leaves the grow alone; its completion still finishes it.
        ([.start, .start, .end(.finished, generation: 1)], [.started(1), .started(nil), .steps(all)]),
        // Shown again after the grow: a new grow, and an old completion can't end it.
        ([.start, .end(.finished, generation: 1), .start, .end(.finished, generation: 1), .end(.finished, generation: 2)],
         [.started(1), .steps(all), .started(2), .steps([]), .steps(all)]),
        // A popup opened in the background: its opener took the keyboard back while it grew, so
        // the end doesn't take it.
        ([.start, .end(.finished, generation: 1, keyElsewhere: true)], [.started(1), .steps([.layout, .showPage])]),
        // A close or promote with no grow running: nothing to undo.
        ([.end(.closed, generation: 0), .end(.promoting, generation: 0)], [.steps([]), .steps([])]),
    ] as [([Call], [Result])])
    func guards(calls: [Call], results: [Result]) {
        var grow = LittleWindowGrow()
        let got = calls.map { call -> Result in
            switch call {
            case .start: return .started(grow.start())
            case let .end(how, generation, keyElsewhere): return .steps(grow.end(how, generation: generation, keyElsewhere: keyElsewhere))
            }
        }
        #expect(got == results)
        #expect(!grow.isGrowing)
    }

    @Test func aPageWindowArrivingWhileItGrowsStaysHidden() {
        var grow = LittleWindowGrow()
        #expect(!grow.hidesNewPageWindow)
        let generation = grow.start()!
        #expect(grow.hidesNewPageWindow)
        _ = grow.end(.finished, generation: generation)
        #expect(!grow.hidesNewPageWindow)
    }
}
