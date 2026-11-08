import Foundation

/// How many history entries the command bar keeps. Over `limit`, the oldest go until `kept`
/// remain: one sort per 500 new addresses, where a sort per visit at the cap went over all 5,000
/// entries on the main thread to drop one.
public enum HistoryCap {
    public static let kept = 5000
    public static let limit = 5500

    /// The addresses to forget: none at or under `limit`, else the oldest visits down to `kept`
    /// (the same visit time: the address that sorts first goes first).
    public static func dropped(_ entries: some Collection<HistoryEntry>, kept: Int = kept, limit: Int = limit) -> [String] {
        guard entries.count > limit else { return [] }
        return entries.sorted { ($0.lastVisit, $0.url) < ($1.lastVisit, $1.url) }.prefix(entries.count - kept).map(\.url)
    }
}
