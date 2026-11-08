import CraCore
import Foundation
import Testing

/// features.md #2: the Little Window open readout, measured before a page is made ahead of time.
struct LittleWindowOpenTimingTests {
    static let requestedWallMs = 1_793_000_000_000.0
    static let ns: UInt64 = 1_000_000

    static func opened() -> LittleWindowOpenTiming {
        var t = LittleWindowOpenTiming(source: "cra-open", requested: 500 * ns, requestedWallMs: requestedWallMs)
        t.mark(.makeStart, at: 504 * ns)
        t.mark(.makeEnd, at: 614 * ns)
        t.mark(.showStart, at: 620 * ns)
        t.mark(.showEnd, at: 742 * ns)
        t.mark(.hostWindow, at: 760 * ns)
        t.mark(.loadingStart, at: 770 * ns)
        return t
    }

    static let page = LittleWindowPagePaint(timeOriginMs: requestedWallMs + 765, firstPaintMs: 80.5, firstContentfulPaintMs: 81,
                                            visible: true, url: "http://127.0.0.1:8124/blank?lw=1")

    @Test(arguments: [
        // Every step, and the page painted.
        (opened(), page, "source=cra-open make_start=4.0 make=110.0 host_window=260.0 show_start=120.0 show=122.0 loading=270.0 "
            + "nav_start=765.0 make_to_nav=761.0 nav_to_paint=80.5 first_paint=845.5 fcp=846.0 visible=1 url=http://127.0.0.1:8124/blank?lw=1"),
        // No answer from the page: its fields are "-", the app's steps stay.
        (opened(), nil, "source=cra-open make_start=4.0 make=110.0 host_window=260.0 show_start=120.0 show=122.0 loading=270.0 "
            + "nav_start=- make_to_nav=- nav_to_paint=- first_paint=- fcp=- visible=- url=-"),
        // Just asked: nothing has happened yet; a hidden page that hasn't painted.
        (LittleWindowOpenTiming(source: "geturl", requested: 9 * ns, requestedWallMs: requestedWallMs),
         LittleWindowPagePaint(timeOriginMs: requestedWallMs + 30.24, firstPaintMs: nil, firstContentfulPaintMs: nil, visible: false, url: "about:blank"),
         "source=geturl make_start=- make=- host_window=- show_start=- show=- loading=- "
            + "nav_start=30.2 make_to_nav=- nav_to_paint=- first_paint=- fcp=- visible=0 url=about:blank"),
    ] as [(LittleWindowOpenTiming, LittleWindowPagePaint?, String)])
    func readout(timing: LittleWindowOpenTiming, page: LittleWindowPagePaint?, line: String) {
        #expect(timing.readout(page: page) == "Cra little timing: " + line)
    }

    @Test func theFirstMarkCounts() {
        var t = Self.opened()
        t.mark(.loadingStart, at: 900 * Self.ns)
        t.mark(.showStart, at: 1 * Self.ns)
        #expect(t.ms(.loadingStart) == 270)
        #expect(t.ms(.showStart) == 120)
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
        // What Runtime.evaluate answers for the script.
        (#"{"result":{"type":"string","value":"{\"timeOrigin\":1793000000765.25,\"firstPaint\":80.5,\"fcp\":81,\"visible\":true,\"url\":\"http://a.test/\"}"}}"#,
         LittleWindowPagePaint(timeOriginMs: 1_793_000_000_765.25, firstPaintMs: 80.5, firstContentfulPaintMs: 81, visible: true, url: "http://a.test/")),
        // Not painted within 3 s.
        (#"{"result":{"type":"string","value":"{\"timeOrigin\":5,\"firstPaint\":null,\"fcp\":null,\"visible\":false,\"url\":\"about:blank\"}"}}"#,
         LittleWindowPagePaint(timeOriginMs: 5, firstPaintMs: nil, firstContentfulPaintMs: nil, visible: false, url: "about:blank")),
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
