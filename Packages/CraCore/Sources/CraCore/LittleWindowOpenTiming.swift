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
        /// The page can be seen: its window shown again after the grow (Chrome hosting keeps it
        /// transparent while the window grows), or the window ordered in (a page in the window).
        case pageShown
    }

    /// What asked for the window: "geturl" (another app's link), "open-urls" (a file or URL
    /// opened with Cra), "cra-open" (cra://open?little=1).
    public let source: String
    /// When the request came in, on the app's clock and on the wall clock the page's own
    /// `timeOrigin` uses.
    public let requested: UInt64
    public let requestedWallMs: Double
    public private(set) var steps: [Step: UInt64] = [:]
    /// At the end of show(): whether Cra was the active app and the window key. macOS can refuse
    /// a test instance's activation; the window may then open behind others, occluded.
    public private(set) var shownActive: Bool?
    public private(set) var shownKey: Bool?
    /// The grow as the window server showed it, when tracing is on (cra://debug?littleGrowTrace=1).
    public var grow: GrowTrace?

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

    /// The first show counts, as for `mark`.
    public mutating func markShown(active: Bool, key: Bool) {
        guard shownActive == nil else { return }
        shownActive = active
        shownKey = key
    }

    /// Milliseconds from the request to `step`; nil until it happens.
    public func ms(_ step: Step) -> Double? {
        steps[step].map { Double(Int64(bitPattern: $0 &- requested)) / 1e6 }
    }

    /// One line. Every value is ms after the request, except `make` and `show` (how long that
    /// step took), `make_to_nav` (how long making the page held its navigation back: what a page
    /// made ahead of time saves) and `nav_to_paint` (the page's own first paint). `seen` is when
    /// the user can see the page: its first paint, or the moment its window was shown if that came
    /// later. "-" is a step that hasn't happened, or a page that didn't answer. `onScreen`: the window wasn't occluded
    /// when the readout was asked for. `vis` is the page's visibility states (state@ms after its
    /// navigation start); `hidden_before_paint` says whether one hid it before its first paint.
    public func readout(page: LittleWindowPagePaint?, onScreen: Bool? = nil) -> String {
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
            ("page_shown", Self.format(ms(.pageShown))),
            ("seen", Self.format(firstPaint.flatMap { paint in ms(.pageShown).map { max(paint, $0) } })),
            ("visible", page.map { $0.visible ? "1" : "0" } ?? "-"),
            ("active", Self.flag(shownActive)),
            ("key", Self.flag(shownKey)),
            ("on_screen", Self.flag(onScreen)),
            ("vis", page?.visibilityChanges.map { $0.isEmpty ? "-" : $0.map { "\($0.state)@\(Self.format($0.ms))" }.joined(separator: ",") } ?? "-"),
            ("hidden_before_paint", Self.flag(page?.hiddenBeforePaint)),
        ]
        // The address goes last: scripts match a readout by the line's end.
        let line = fields.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
        return "Cra little timing: " + line + (grow.map { " " + $0.readout } ?? "") + " url=\(page?.url ?? "-")"
    }

    private static func difference(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return a - b
    }

    private static func flag(_ b: Bool?) -> String { b.map { $0 ? "1" : "0" } ?? "-" }

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
    /// The page's visibility-state performance entries in order (the first is the state it
    /// started in); nil when the engine has none. Chromium hides a page whose window is occluded.
    public let visibilityChanges: [VisibilityChange]?

    public struct VisibilityChange: Equatable, Sendable {
        public let state: String
        public let ms: Double

        public init(state: String, ms: Double) {
            self.state = state
            self.ms = ms
        }
    }

    public init(timeOriginMs: Double, firstPaintMs: Double?, firstContentfulPaintMs: Double?, visible: Bool, url: String,
                visibilityChanges: [VisibilityChange]? = nil) {
        self.timeOriginMs = timeOriginMs
        self.firstPaintMs = firstPaintMs
        self.firstContentfulPaintMs = firstContentfulPaintMs
        self.visible = visible
        self.url = url
        self.visibilityChanges = visibilityChanges
    }

    /// Whether the page was hidden at any time up to its first paint (or ever, before it painted);
    /// nil without visibility entries.
    public var hiddenBeforePaint: Bool? {
        guard let changes = visibilityChanges, !changes.isEmpty else { return nil }
        return changes.contains { $0.state == "hidden" && $0.ms <= (firstPaintMs ?? .infinity) }
    }

    public static let script = """
        new Promise(done => {
          const since = Date.now();
          const look = () => {
            const paint = name => performance.getEntriesByName(name, 'paint')[0]?.startTime ?? null;
            if (paint('first-paint') === null && Date.now() - since < 3000) { setTimeout(look, 50); return; }
            done(JSON.stringify({timeOrigin: performance.timeOrigin, firstPaint: paint('first-paint'),
              fcp: paint('first-contentful-paint'), visible: document.visibilityState === 'visible', url: location.href,
              vis: performance.getEntriesByType('visibility-state').map(e => [e.name, e.startTime])}));
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
        let changes = (fields["vis"] as? [[Any]])?.compactMap { entry -> VisibilityChange? in
            guard entry.count == 2, let state = entry[0] as? String, let ms = entry[1] as? Double else { return nil }
            return VisibilityChange(state: state, ms: ms)
        }
        self.init(timeOriginMs: timeOrigin, firstPaintMs: fields["firstPaint"] as? Double,
                  firstContentfulPaintMs: fields["fcp"] as? Double, visible: fields["visible"] as? Bool ?? false, url: url,
                  visibilityChanges: changes)
    }
}
