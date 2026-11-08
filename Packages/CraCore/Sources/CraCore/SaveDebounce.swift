import Foundation

/// When a debounced save writes its file: `delay` after the last save asked, but no later than
/// `maxWait` after the first one not yet written. Without the cap, a tab whose title changes
/// more often than every 2 s (an unread count, a timer) put off every sidebar.json write,
/// structural edits included, for as long as it kept changing.
public struct SaveDebounce: Equatable, Sendable {
    public static let defaultMaxWait: TimeInterval = 10

    public let maxWait: TimeInterval
    /// When the oldest save not yet written was asked; nil when everything is written.
    public private(set) var waitingSince: Date?

    public init(maxWait: TimeInterval = SaveDebounce.defaultMaxWait) {
        self.maxWait = maxWait
    }

    /// A save asked at `now`: when to write. A later save moves the write to its own deadline,
    /// earlier or later, within the cap.
    public mutating func request(at now: Date, delay: TimeInterval) -> Date {
        let first = waitingSince ?? now
        waitingSince = first
        return min(now.addingTimeInterval(delay), first.addingTimeInterval(maxWait))
    }

    /// The file is being written: the next save starts a new wait.
    public mutating func written() {
        waitingSince = nil
    }
}
