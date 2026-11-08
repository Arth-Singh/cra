import CraCore
import Foundation
import Testing

struct SaveDebounceTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// The audit's case: a structural edit (a 0.4 s save), then the tab's title changes 0.25 s
    /// later and every 1 s after that for 60 s (2 s saves). A pure trailing debounce wrote
    /// nothing until the title stopped; the cap writes 10 s after the oldest unwritten save.
    @Test func titleChangingEverySecondStillWrites() {
        var d = SaveDebounce()
        var due: Date?
        var writes: [TimeInterval] = []
        let saves: [(at: TimeInterval, delay: TimeInterval)] = [(0, 0.4)] + (0..<60).map { (0.25 + TimeInterval($0), 2) }
        for save in saves {
            let now = t0.addingTimeInterval(save.at)
            if let due, due <= now {
                writes.append(due.timeIntervalSince(t0))
                d.written()
            }
            due = d.request(at: now, delay: save.delay)
        }
        #expect(writes == [10, 20.25, 30.25, 40.25, 50.25])
        #expect(due == t0.addingTimeInterval(60.25), "the last wait is capped too")
    }

    @Test func trailingWithinTheCap() {
        var d = SaveDebounce()
        #expect(d.request(at: t0, delay: 2) == t0.addingTimeInterval(2))
        #expect(d.request(at: t0.addingTimeInterval(1), delay: 2) == t0.addingTimeInterval(3), "a save within the delay moves the write later")
        #expect(d.request(at: t0.addingTimeInterval(1.5), delay: 0.4) == t0.addingTimeInterval(1.9), "a shorter delay moves it earlier")
        #expect(d.request(at: t0.addingTimeInterval(9), delay: 2) == t0.addingTimeInterval(10), "never past the first save plus 10 s")
        #expect(d.waitingSince == t0)
        d.written()
        #expect(d.waitingSince == nil)
        #expect(d.request(at: t0.addingTimeInterval(11), delay: 2) == t0.addingTimeInterval(13), "after a write, a new wait")
    }

    @Test func delayLongerThanTheCap() {
        var d = SaveDebounce(maxWait: 3)
        #expect(d.request(at: t0, delay: 5) == t0.addingTimeInterval(3), "history's 5 s save under a 3 s cap")
    }
}
