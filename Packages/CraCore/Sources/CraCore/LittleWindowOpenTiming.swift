import Foundation

/// How long a Little Window took to open, step by step: features.md #2 measures this before it
/// makes a page ahead of time. The app marks its steps on its monotonic clock (`Perf.now()`,
/// nanoseconds); the page reports its own navigation start (`performance.timeOrigin`, ms since
/// 1970) and paints. `cra://debug?littleTiming=1` logs `readout(page:)`.
public struct LittleWindowOpenTiming: Equatable, Sendable {
    public enum Step: String, CaseIterable, Sendable {
        /// PageEngines.makeBrowser was called, and returned.
        case makeStart, makeEnd
        /// Chrome hosting handed over the page's window.
        case hostWindow
        /// show(): the window grows from the pointer, a 120 ms animation on the main thread.
        case showStart, showEnd
        /// The page's first loading state.
        case loadingStart
    }

    /// What asked for the window: "geturl" (another app's link), "open-urls" (a file or URL
    /// opened with Cra), "cra-open" (cra://open?little=1).
    public let source: String
    /// When the request came in, on the app's clock and on the wall clock the page's own
    /// `timeOrigin` uses.
    public let requested: UInt64
    public let requestedWallMs: Double
    public private(set) var steps: [Step: UInt64] = [:]

    public init(source: String, requested: UInt64, requestedWallMs: Double) {
        self.source = source
        self.requested = requested
        self.requestedWallMs = requestedWallMs
    }

    /// A request that comes in now.
    public static func request(_ source: String) -> Self {
        Self(source: source, requested: now(), requestedWallMs: Date().timeIntervalSince1970 * 1000)
    }

    /// Monotonic nanoseconds, the clock `Perf.now()` reads; it stops while the Mac sleeps. The
    /// readout is not the performance recorder, which only some files may reach (scripts/lint.py).
    public static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    /// The first time counts: a later load or show doesn't move the open's step.
    public mutating func mark(_ step: Step, at time: UInt64 = LittleWindowOpenTiming.now()) {
        if steps[step] == nil { steps[step] = time }
    }

    /// Milliseconds from the request to `step`; nil until it happens.
    public func ms(_ step: Step) -> Double? {
        steps[step].map { Double(Int64(bitPattern: $0 &- requested)) / 1e6 }
    }

    /// One line. Every value is ms after the request, except `make` and `show` (how long that
    /// step took), `make_to_nav` (how long making the page held its navigation back: what a page
    /// made ahead of time saves) and `nav_to_paint` (the page's own first paint). "-" is a step
    /// that hasn't happened, or a page that didn't answer.
    public func readout(page: LittleWindowPagePaint?) -> String {
        let navStart = page.map { $0.timeOriginMs - requestedWallMs }
        let firstPaint = page?.firstPaintMs.flatMap { fp in navStart.map { $0 + fp } }
        let fields: [(String, String)] = [
            ("source", source),
            ("make_start", Self.format(ms(.makeStart))),
            ("make", Self.format(Self.difference(ms(.makeEnd), ms(.makeStart)))),
            ("host_window", Self.format(ms(.hostWindow))),
            ("show_start", Self.format(ms(.showStart))),
            ("show", Self.format(Self.difference(ms(.showEnd), ms(.showStart)))),
            ("loading", Self.format(ms(.loadingStart))),
            ("nav_start", Self.format(navStart)),
            ("make_to_nav", Self.format(Self.difference(navStart, ms(.makeStart)))),
            ("nav_to_paint", Self.format(page?.firstPaintMs)),
            ("first_paint", Self.format(firstPaint)),
            ("fcp", Self.format(page?.firstContentfulPaintMs.flatMap { fcp in navStart.map { $0 + fcp } })),
            ("visible", page.map { $0.visible ? "1" : "0" } ?? "-"),
            ("url", page?.url ?? "-"),
        ]
        return "Cra little timing: " + fields.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
    }

    private static func difference(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return a - b
    }

    private static func format(_ ms: Double?) -> String {
        ms.map { String(format: "%.1f", $0) } ?? "-"
    }
}

/// The page's own timing: `script`, evaluated in the page with Runtime.evaluate (returnByValue,
/// awaitPromise), answers with it once the page has painted, or after 3 s without a paint.
public struct LittleWindowPagePaint: Equatable, Sendable {
    /// The navigation's start, in ms since 1970 (`performance.timeOrigin`).
    public let timeOriginMs: Double
    /// The paint entries, in ms after `timeOriginMs`; nil before the page paints.
    public let firstPaintMs: Double?
    public let firstContentfulPaintMs: Double?
    public let visible: Bool
    public let url: String

    public init(timeOriginMs: Double, firstPaintMs: Double?, firstContentfulPaintMs: Double?, visible: Bool, url: String) {
        self.timeOriginMs = timeOriginMs
        self.firstPaintMs = firstPaintMs
        self.firstContentfulPaintMs = firstContentfulPaintMs
        self.visible = visible
        self.url = url
    }

    public static let script = """
        new Promise(done => {
          const since = Date.now();
          const look = () => {
            const paint = name => performance.getEntriesByName(name, 'paint')[0]?.startTime ?? null;
            if (paint('first-paint') === null && Date.now() - since < 3000) { setTimeout(look, 50); return; }
            done(JSON.stringify({timeOrigin: performance.timeOrigin, firstPaint: paint('first-paint'),
              fcp: paint('first-contentful-paint'), visible: document.visibilityState === 'visible', url: location.href}));
          };
          look();
        })
        """

    /// From DevTools' reply to `script`: {"result":{"type":"string","value":"{…}"}}. Nil when the
    /// reply has no such value (the page threw, or isn't there).
    public init?(devToolsResult: String) {
        guard let reply = try? JSONSerialization.jsonObject(with: Data(devToolsResult.utf8)) as? [String: Any],
              let value = (reply["result"] as? [String: Any])?["value"] as? String,
              let fields = try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
              let timeOrigin = fields["timeOrigin"] as? Double,
              let url = fields["url"] as? String else { return nil }
        self.init(timeOriginMs: timeOrigin, firstPaintMs: fields["firstPaint"] as? Double,
                  firstContentfulPaintMs: fields["fcp"] as? Double, visible: fields["visible"] as? Bool ?? false, url: url)
    }
}
