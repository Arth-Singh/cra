import Foundation

/// Which hidden pages tab sleeping asks to close. By default it is Arc's (GitHub #136): a page out
/// of sight for 4 hours closes unless it is one of the 10 tabs used last. Settings ▸ Tabs can
/// change the time, turn the clock off, or close pages while macOS reports memory pressure
/// (GitHub #153). The probes in BrowserManager still decide whether a candidate may close.
public struct TabSleepPolicy: Equatable, Sendable {
    public enum Reason: String, Sendable { case timer, memoryPressure, splitCopy }

    /// A page this long out of sight, and silent as long, is a candidate.
    public var hiddenFor: TimeInterval
    /// The tabs on screen and the ones hidden most recently, `protectedRecentTabs` in all, stay.
    public var keepsRecentTabs: Bool
    /// At most this many pages are asked in one pass (nil: all of them).
    public var limit: Int?
    public var reason: Reason

    public init(hiddenFor: TimeInterval, keepsRecentTabs: Bool = true, limit: Int? = nil, reason: Reason = .timer) {
        self.hiddenFor = hiddenFor
        self.keepsRecentTabs = keepsRecentTabs
        self.limit = limit
        self.reason = reason
    }

    /// Arc never discards the pages of the 10 tabs used last (WebContentLifecycleOptimization's
    /// protectedLRUTabCount).
    public static let protectedRecentTabs = 10

    /// "Force tabs out of memory after:". Arc's 4 hours, or longer, keep the 10 tabs used last;
    /// a shorter time is asked for to close those too, since they hold most of the memory.
    public static func timer(_ after: TabSleepThreshold) -> TabSleepPolicy {
        TabSleepPolicy(hiddenFor: after.seconds, keepsRecentTabs: after.seconds >= TabSleepThreshold.fourHours.seconds)
    }

    /// "…when the Mac is short of memory": the 3 pages hidden longest, whatever their rank, but
    /// none left in the last 5 minutes, so a tab just left (or just woken) isn't closed again.
    public static let memoryPressure = TabSleepPolicy(hiddenFor: 5 * 60, keepsRecentTabs: false, limit: 3, reason: .memoryPressure)

    /// A pinned tab that a split pane copied (Arc): its page sleeps at once, the copy shows it.
    public static let splitCopy = TabSleepPolicy(hiddenFor: 0, keepsRecentTabs: false, limit: 1, reason: .splitCopy)

    /// At macOS's critical level (GitHub #237): a third of the pages a pressure sweep could close,
    /// and at least the warning level's 3, hidden longest first over every window. A burst of 40
    /// hidden pages then drains in 3 sweeps; at 3 a sweep it took 13, one every 2 minutes, and the
    /// 15-minute clock closed them first while a 16 GB Mac swapped.
    public static func criticalMemoryPressure(candidates: Int) -> TabSleepPolicy {
        var policy = memoryPressure
        policy.limit = max(memoryPressure.limit ?? 0, (candidates + 2) / 3)
        return policy
    }

    /// macOS reports a level for a while after pages close, so a sweep waits this long for the
    /// last one to tell before taking more.
    public static let pressureSweepInterval: TimeInterval = 90
    /// At critical a sweep doesn't wait for the last one to tell: every minute's pass sweeps. Under
    /// 60 s, so the pass's own jitter doesn't skip one (90 s skipped every second pass).
    public static let criticalPressureSweepInterval: TimeInterval = 55

    /// Whether the minute's pass, or a level macOS just reported, sweeps for memory pressure:
    /// `pressureSweepInterval` after the last sweep at warning, `criticalPressureSweepInterval` at
    /// critical, and at once when the level rose to critical since the last sweep (`lastLevel`).
    public static func sweepsForPressure(_ pressure: PerfSystemSample.Pressure, enabled: Bool, lastSweep: Date?,
                                         lastLevel: PerfSystemSample.Pressure? = nil, now: Date) -> Bool {
        guard enabled, pressure.isShort else { return false }
        guard let lastSweep else { return true }
        if pressure == .critical, lastLevel != .critical { return true }
        let wait = pressure == .critical ? criticalPressureSweepInterval : pressureSweepInterval
        return now.timeIntervalSince(lastSweep) >= wait
    }

    /// How many pages each window asks when one limit covers every window: the `limit` pages
    /// hidden longest over all of them. `hiddenAt[w]` is when window w's candidates went out of sight.
    public static func quotas(_ hiddenAt: [[Date]], limit: Int) -> [Int] {
        let ranked = hiddenAt.enumerated().flatMap { w, dates in dates.map { ($0, w) } }.sorted { $0 < $1 }
        var quotas = [Int](repeating: 0, count: hiddenAt.count)
        for (_, w) in ranked.prefix(max(limit, 0)) { quotas[w] += 1 }
        return quotas
    }

    /// One memory-pressure sweep: its policy and each window's limit. At warning 3 pages per window;
    /// at critical `criticalMemoryPressure` of every window's candidates, the oldest over all of them.
    /// `hiddenAt[w]` is when window w's candidates went out of sight.
    public static func pressureSweep(_ level: PerfSystemSample.Pressure, hiddenAt: [[Date]]) -> (policy: TabSleepPolicy, limits: [Int]) {
        guard level == .critical else { return (memoryPressure, hiddenAt.map { _ in memoryPressure.limit ?? 0 }) }
        let policy = criticalMemoryPressure(candidates: hiddenAt.reduce(0) { $0 + $1.count })
        return (policy, quotas(hiddenAt, limit: policy.limit ?? 0))
    }

    /// What a sweep did, summed over windows, so a sweep that closes nothing says why (#237: two
    /// sweeps under pressure left no line but "closing up to 3 pages").
    public struct Sweep: Equatable, Sendable {
        /// Out of sight for `hiddenFor` and not protected (`candidates(_:visible:protectedRecent:now:)`).
        public var candidates = 0
        /// Asked to sleep; each one's discard or refusal has its own line.
        public var asked = 0
        /// Held awake before being asked (`Hold`).
        public var held = 0
        /// Refused less than BrowserManager's back-off ago, asked again after it.
        public var waiting = 0

        public init(candidates: Int = 0, asked: Int = 0, held: Int = 0, waiting: Int = 0) {
            self.candidates = candidates
            self.asked = asked
            self.held = held
            self.waiting = waiting
        }

        public static func + (a: Sweep, b: Sweep) -> Sweep {
            Sweep(candidates: a.candidates + b.candidates, asked: a.asked + b.asked, held: a.held + b.held, waiting: a.waiting + b.waiting)
        }

        /// The sweep's line in cra.log. `limit` is per window at warning, over every window at critical.
        public func line(level: PerfSystemSample.Pressure, limit: Int, hiddenFor: TimeInterval) -> String {
            let scope = level == .critical ? "over every window" : "per window"
            let head = "tab sleep: memory pressure \(level.rawValue), limit \(limit) \(scope)"
            if candidates == 0 { return "\(head): nothing to close, no page out of sight for \(Int(hiddenFor / 60)) min" }
            var line = "\(head): asked \(asked) of \(candidates) pages"
            let kept = [(held, "held awake"), (waiting, "waiting after a refusal")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
            if !kept.isEmpty { line += " (\(kept.joined(separator: ", ")))" }
            return line
        }
    }

    /// A page as tab sleeping sees it: when it went off screen (nil while shown) and when it last
    /// played or stopped playing sound.
    public struct Page: Equatable, Sendable {
        public var id: UUID
        public var hiddenAt: Date?
        public var audibleAt: Date?

        public init(id: UUID, hiddenAt: Date?, audibleAt: Date? = nil) {
            self.id = id
            self.hiddenAt = hiddenAt
            self.audibleAt = audibleAt
        }
    }

    /// The tabs on screen, then the ones hidden most recently, `count` in all.
    public static func recentlyShown(_ pages: [Page], visible: [UUID], count: Int) -> Set<UUID> {
        let hidden = pages.compactMap { p in p.hiddenAt.map { (p.id, $0) } }.sorted { $0.1 > $1.1 }.map(\.0)
        return Set((visible + hidden).prefix(count))
    }

    /// A candidate's page as BrowserManager sees it before asking it anything.
    public struct PageState: Equatable, Sendable {
        public var discarded = false
        public var hiddenAt: Date?
        public var audibleAt: Date?
        public var visible = false
        public var created = true
        public var closed = false
        public var loading = false
        public var pictureInPicture = false
        public var capturing = false
        public var audible = false
        public var devTools = false

        public init(discarded: Bool = false, hiddenAt: Date?, audibleAt: Date? = nil, visible: Bool = false, created: Bool = true,
                    closed: Bool = false, loading: Bool = false, pictureInPicture: Bool = false, capturing: Bool = false,
                    audible: Bool = false, devTools: Bool = false) {
            self.discarded = discarded
            self.hiddenAt = hiddenAt
            self.audibleAt = audibleAt
            self.visible = visible
            self.created = created
            self.closed = closed
            self.loading = loading
            self.pictureInPicture = pictureInPicture
            self.capturing = capturing
            self.audible = audible
            self.devTools = devTools
        }
    }

    /// Why a page stays awake without being asked, the first that holds (GitHub #214: a sweep
    /// that came 27 passes late could not say which). The raw values are `sleepSkip`'s keys in
    /// perf.json and the words in cra.log.
    public enum Hold: String, CaseIterable, Sendable {
        case discarded, shown, sound, notCreated, closing, loading, pictureInPicture, capturing, audible, devTools
    }

    /// nil when the page may be asked to sleep: out of sight and silent since before `cutoff`, made,
    /// not loading, and in no Picture in Picture, capture or DevTools.
    public static func hold(_ p: PageState, before cutoff: Date) -> Hold? {
        if p.discarded { return .discarded }
        if p.visible || p.hiddenAt.map({ $0 < cutoff }) != true { return .shown }
        if p.audibleAt.map({ $0 < cutoff }) == false { return .sound }
        if !p.created { return .notCreated }
        if p.closed { return .closing }
        if p.loading { return .loading }
        if p.pictureInPicture { return .pictureInPicture }
        if p.capturing { return .capturing }
        if p.audible { return .audible }
        if p.devTools { return .devTools }
        return nil
    }

    /// Chromium's freezing policy sees what Cra's page probes can't: a call with the camera and
    /// microphone off (an open RTCPeerConnection), a USB, Bluetooth, HID or serial device, a
    /// mirrored or captured tab. `reasons` are its CannotFreezeReasonToString names for the page
    /// and the pages connected to it (Cra.getFreezingState); "" when none of them keeps it awake.
    public static func refusal(freezingReasons reasons: [String]) -> String {
        if reasons.contains("has an active WebRTC connection") { return "call" }
        if reasons.contains(where: { $0.hasPrefix("connected to ") }) { return "device" }
        if reasons.contains(where: { $0.hasPrefix("capturing ") || $0 == "being mirrored" }) { return "capturing" }
        return ""
    }

    /// The pages to ask, hidden longest first. The caller skips the ones its probes refuse
    /// before it counts toward `limit`.
    public func candidates(_ pages: [Page], visible: [UUID], protectedRecent: Int = protectedRecentTabs, now: Date) -> [UUID] {
        let cutoff = now.addingTimeInterval(-hiddenFor)
        let kept = keepsRecentTabs ? Self.recentlyShown(pages, visible: visible, count: protectedRecent) : []
        return pages
            .filter { p in
                guard let hidden = p.hiddenAt, hidden < cutoff, !visible.contains(p.id), !kept.contains(p.id) else { return false }
                return p.audibleAt.map { $0 < cutoff } ?? true
            }
            .sorted { ($0.hiddenAt!, $0.id.uuidString) < ($1.hiddenAt!, $1.id.uuidString) }
            .map(\.id)
    }
}

extension PerfSystemSample.Pressure {
    /// macOS warns while the compressor works hard; critical is the same state further along.
    public var isShort: Bool { self == .warning || self == .critical }
}

/// Settings ▸ Tabs ▸ "Force tabs out of memory after:" (GitHub #153). Arc's 4 hours by default;
/// the checkbox, not a case, turns the clock off.
public enum TabSleepThreshold: String, Codable, CaseIterable, Identifiable {
    case fifteenMinutes, thirtyMinutes, oneHour, twoHours, fourHours, eightHours
    public var id: String { rawValue }
    public var seconds: TimeInterval {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 3600
        case .twoHours: return 2 * 3600
        case .fourHours: return 4 * 3600
        case .eightHours: return 8 * 3600
        }
    }
    public var label: String {
        switch self {
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .fourHours: return "4 hours"
        case .eightHours: return "8 hours"
        }
    }
}
