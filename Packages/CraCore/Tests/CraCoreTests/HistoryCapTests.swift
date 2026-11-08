import CraCore
import Foundation
import Testing

struct HistoryCapTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func entries(_ n: Int) -> [HistoryEntry] {
        (0..<n).map { HistoryEntry(url: "https://example.test/\($0)", title: "", lastVisit: t0.addingTimeInterval(TimeInterval($0)), visitCount: 1) }
    }

    @Test func dropsInBatches() {
        #expect(HistoryCap.dropped(entries(5500)).isEmpty, "up to 5,500 stay")
        let dropped = HistoryCap.dropped(entries(5501))
        #expect(dropped.count == 501, "over 5,500: back to 5,000")
        #expect(dropped == (0..<501).map { "https://example.test/\($0)" }, "the oldest visits go")
        #expect(HistoryCap.dropped(entries(3)).isEmpty)
        #expect(HistoryCap.dropped([HistoryEntry]()).isEmpty)
    }

    @Test func sameVisitTimeIsOrderedByAddress() {
        let same = ["https://b.test", "https://a.test", "https://c.test"].map { HistoryEntry(url: $0, title: "", lastVisit: t0, visitCount: 1) }
        #expect(HistoryCap.dropped(same, kept: 1, limit: 2) == ["https://a.test", "https://b.test"])
    }
}
