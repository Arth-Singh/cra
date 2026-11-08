import CoreGraphics
import CraCore
import Foundation
import Testing

/// features.md #2: the Little Window open readout, measured before a page is made ahead of time.
struct LittleWindowOpenTimingTests {
    typealias Change = LittleWindowPagePaint.VisibilityChange
    static let requestedWallMs = 1_793_000_000_000.0
    static let ns: UInt64 = 1_000_000

    static func opened() -> LittleWindowOpenTiming {
        var t = LittleWindowOpenTiming(source: "cra-open", requested: 500 * ns, requestedWallMs: requestedWallMs)
        t.mark(.makeStart, at: 504 * ns)
        t.mark(.makeEnd, at: 614 * ns)
        t.mark(.showStart, at: 620 * ns)
        t.mark(.showEnd, at: 742 * ns)
        t.markShown(active: true, key: false)
        t.mark(.hostWindow, at: 760 * ns)
        t.mark(.loadingStart, at: 770 * ns)
        return t
    }

    static let page = LittleWindowPagePaint(timeOriginMs: requestedWallMs + 765, firstPaintMs: 80.5, firstContentfulPaintMs: 81,
                                            visible: true, url: "http://127.0.0.1:8124/blank?lw=1",
                                            visibilityChanges: [Change(state: "visible", ms: 0)])

    @Test(arguments: [
        // Every step, and the page painted on screen.
        (opened(), page, true, "source=cra-open make_start=4.0 make=110.0 host_window=260.0 show_start=120.0 show=122.0 loading=270.0 "
            + "nav_start=765.0 make_to_nav=761.0 nav_to_paint=80.5 first_paint=845.5 fcp=846.0 page_shown=- seen=- visible=1 active=1 key=0 on_screen=1 "
            + "vis=visible@0.0 hidden_before_paint=0 url=http://127.0.0.1:8124/blank?lw=1"),
        // No answer from the page: its fields are "-", the app's steps stay.
        (opened(), nil, nil, "source=cra-open make_start=4.0 make=110.0 host_window=260.0 show_start=120.0 show=122.0 loading=270.0 "
            + "nav_start=- make_to_nav=- nav_to_paint=- first_paint=- fcp=- page_shown=- seen=- visible=- active=1 key=0 on_screen=- "
            + "vis=- hidden_before_paint=- url=-"),
        // Just asked: nothing has happened yet; a covered page that hasn't painted, no visibility entries.
        (LittleWindowOpenTiming(source: "geturl", requested: 9 * ns, requestedWallMs: requestedWallMs),
         LittleWindowPagePaint(timeOriginMs: requestedWallMs + 30.24, firstPaintMs: nil, firstContentfulPaintMs: nil, visible: false, url: "about:blank"),
         false,
         "source=geturl make_start=- make=- host_window=- show_start=- show=- loading=- "
            + "nav_start=30.2 make_to_nav=- nav_to_paint=- first_paint=- fcp=- page_shown=- seen=- visible=0 active=- key=- on_screen=0 "
            + "vis=- hidden_before_paint=- url=about:blank"),
        // Opened behind other windows: hidden first, shown later, painted then.
        (opened(), LittleWindowPagePaint(timeOriginMs: requestedWallMs + 765, firstPaintMs: 300, firstContentfulPaintMs: nil, visible: true,
                                         url: "http://a.test/", visibilityChanges: [Change(state: "hidden", ms: 0), Change(state: "visible", ms: 250.5)]),
         true,
         "source=cra-open make_start=4.0 make=110.0 host_window=260.0 show_start=120.0 show=122.0 loading=270.0 "
            + "nav_start=765.0 make_to_nav=761.0 nav_to_paint=300.0 first_paint=1065.0 fcp=- page_shown=- seen=- visible=1 active=1 key=0 on_screen=1 "
            + "vis=hidden@0.0,visible@250.5 hidden_before_paint=1 url=http://a.test/"),
        // The page window shown after the grow, later than the page painted (Chrome hosting): seen
        // is the later of the two. With a grow trace, its fields come before the address.
        ({ () -> LittleWindowOpenTiming in
            var t = opened()
            t.mark(.pageShown, at: 900 * ns)
            t.grow = GrowTrace(samples: [.init(ms: 0, frame: CGRect(x: 0, y: 0, width: 48, height: 30)),
                                         .init(ms: 120, frame: CGRect(x: 0, y: 0, width: 648, height: 480))],
                               target: CGRect(x: 0, y: 0, width: 648, height: 480))
            return t
        }(), page, true,
         "source=cra-open make_start=4.0 make=110.0 host_window=260.0 show_start=120.0 show=122.0 loading=270.0 "
            + "nav_start=765.0 make_to_nav=761.0 nav_to_paint=80.5 first_paint=845.5 fcp=846.0 page_shown=400.0 seen=845.5 visible=1 active=1 key=0 "
            + "on_screen=1 vis=visible@0.0 hidden_before_paint=0 grow_ms=120.0 grow_from=48x30 grow_to=648x480 "
            + "grow_curve=0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00 url=http://127.0.0.1:8124/blank?lw=1"),
        // Painted before its window was shown: seen is the showing.
        ({ () -> LittleWindowOpenTiming in
            var t = opened()
            t.mark(.pageShown, at: 1500 * ns)
            return t
        }(), page, true,
         "source=cra-open make_start=4.0 make=110.0 host_window=260.0 show_start=120.0 show=122.0 loading=270.0 "
            + "nav_start=765.0 make_to_nav=761.0 nav_to_paint=80.5 first_paint=845.5 fcp=846.0 page_shown=1000.0 seen=1000.0 visible=1 active=1 key=0 "
            + "on_screen=1 vis=visible@0.0 hidden_before_paint=0 url=http://127.0.0.1:8124/blank?lw=1"),
    ] as [(LittleWindowOpenTiming, LittleWindowPagePaint?, Bool?, String)])
    func readout(timing: LittleWindowOpenTiming, page: LittleWindowPagePaint?, onScreen: Bool?, line: String) {
        #expect(timing.readout(page: page, onScreen: onScreen) == "Cra little timing: " + line)
    }

    @Test func theFirstMarkCounts() {
        var t = Self.opened()
        t.mark(.loadingStart, at: 900 * Self.ns)
        t.mark(.showStart, at: 1 * Self.ns)
        t.markShown(active: false, key: true)
        #expect(t.ms(.loadingStart) == 270)
        #expect(t.ms(.showStart) == 120)
        #expect(t.shownActive == true && t.shownKey == false)
        #expect(LittleWindowOpenTiming(source: "geturl", requested: 0, requestedWallMs: 0).ms(.makeEnd) == nil)
    }

    /// The app's calls: a request now, and its steps marked as they happen.
    @Test func timedNow() {
        let before = Date().timeIntervalSince1970 * 1000
        var t = LittleWindowOpenTiming.request("geturl")
        t.mark(.makeStart)
        #expect(t.source == "geturl")
        #expect(abs(t.requestedWallMs - before) < 1000)
        #expect((0..<1000).contains(t.ms(.makeStart)!))
    }

    @Test(arguments: [
        ([Change(state: "visible", ms: 0)], 80, false),
        // Hidden from the start (an occluded window), painted once shown.
        ([Change(state: "hidden", ms: 0), Change(state: "visible", ms: 120)], 150, true),
        // Hidden after it painted: the paint counts.
        ([Change(state: "visible", ms: 0), Change(state: "hidden", ms: 200)], 80, false),
        // Hidden at the paint's own time.
        ([Change(state: "visible", ms: 0), Change(state: "hidden", ms: 80)], 80, true),
        // Never painted, hidden on the way.
        ([Change(state: "visible", ms: 0), Change(state: "hidden", ms: 50)], nil, true),
        ([Change(state: "visible", ms: 0)], nil, false),
        // No entries: unknown.
        ([], 80, nil),
        (nil, 80, nil),
    ] as [([Change]?, Double?, Bool?)])
    func hiddenBeforePaint(changes: [Change]?, firstPaint: Double?, hidden: Bool?) {
        let page = LittleWindowPagePaint(timeOriginMs: 0, firstPaintMs: firstPaint, firstContentfulPaintMs: nil, visible: true, url: "http://a.test/",
                                         visibilityChanges: changes)
        #expect(page.hiddenBeforePaint == hidden)
    }

    @Test(arguments: [
        // What Runtime.evaluate answers for the script.
        (#"{"result":{"type":"string","value":"{\"timeOrigin\":1793000000765.25,\"firstPaint\":80.5,\"fcp\":81,\"visible\":true,\"url\":\"http://a.test/\",\"vis\":[[\"hidden\",0],[\"visible\",12.5]]}"}}"#,
         LittleWindowPagePaint(timeOriginMs: 1_793_000_000_765.25, firstPaintMs: 80.5, firstContentfulPaintMs: 81, visible: true, url: "http://a.test/",
                               visibilityChanges: [Change(state: "hidden", ms: 0), Change(state: "visible", ms: 12.5)])),
        // Not painted within 3 s; an engine without visibility entries.
        (#"{"result":{"type":"string","value":"{\"timeOrigin\":5,\"firstPaint\":null,\"fcp\":null,\"visible\":false,\"url\":\"about:blank\"}"}}"#,
         LittleWindowPagePaint(timeOriginMs: 5, firstPaintMs: nil, firstContentfulPaintMs: nil, visible: false, url: "about:blank")),
        // A malformed entry is left out.
        (#"{"result":{"type":"string","value":"{\"timeOrigin\":5,\"visible\":true,\"url\":\"about:blank\",\"vis\":[[\"visible\"],[\"visible\",3]]}"}}"#,
         LittleWindowPagePaint(timeOriginMs: 5, firstPaintMs: nil, firstContentfulPaintMs: nil, visible: true, url: "about:blank",
                               visibilityChanges: [Change(state: "visible", ms: 3)])),
        // The page threw, or the reply isn't the script's.
        (#"{"result":{"type":"object","subtype":"error","description":"ReferenceError"},"exceptionDetails":{}}"#, nil),
        (#"{"result":{"type":"string","value":"{\"firstPaint\":1}"}}"#, nil),
        (#"{"result":{"type":"string","value":"not json"}}"#, nil),
        ("", nil),
    ] as [(String, LittleWindowPagePaint?)])
    func pageFromDevTools(reply: String, page: LittleWindowPagePaint?) {
        #expect(LittleWindowPagePaint(devToolsResult: reply) == page)
    }
}
