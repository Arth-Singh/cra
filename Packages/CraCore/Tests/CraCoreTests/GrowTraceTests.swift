import CoreGraphics
import CraCore
import Testing

/// features.md #2b: the grow as the window server showed it, for the look check.
struct GrowTraceTests {
    static func frame(_ width: Double) -> CGRect { CGRect(x: 100, y: 100, width: width, height: width * 0.75) }

    @Test func traceOfAGrow() {
        // 8 ms frames: held at 40 wide for two frames, then 40 → 640 over 96 ms, then held.
        let widths: [Double] = [40, 40, 40, 64, 112, 184, 268, 352, 436, 508, 568, 604, 628, 640, 640, 640]
        let trace = GrowTrace(samples: widths.enumerated().map { .init(ms: Double($0.offset) * 8, frame: Self.frame($0.element)) },
                              target: Self.frame(640))
        #expect(trace.from == Self.frame(40))
        #expect(trace.to == Self.frame(640))
        #expect(trace.durationMs == 88)   // from the last frame at 40 (16 ms) to the first at 640 (104 ms)
        // At 16 + 8.8 k ms, the last frame before: 64, 112, 184 … 604 wide.
        #expect(trace.curve == [0.04, 0.12, 0.24, 0.38, 0.52, 0.66, 0.78, 0.88, 0.94])
        #expect(trace.readout == "grow_ms=88.0 grow_from=40x30 grow_to=640x480 grow_curve=0.04,0.12,0.24,0.38,0.52,0.66,0.78,0.88,0.94")
    }

    @Test(arguments: [
        // Already at its size: nothing moved.
        ([40, 40, 40], 40, "grow_ms=- grow_from=40x30 grow_to=40x30 grow_curve=-"),
        // No samples at all.
        ([], 640, "grow_ms=- grow_from=- grow_to=- grow_curve=-"),
        // Still moving when the trace ended: it never reached 640, so there is no move to measure.
        ([40, 40, 200, 400], 640, "grow_ms=- grow_from=40x30 grow_to=400x300 grow_curve=-"),
    ] as [([Double], Double, String)])
    func traceWithoutAMove(widths: [Double], target: Double, readout: String) {
        let trace = GrowTrace(samples: widths.enumerated().map { .init(ms: Double($0.offset) * 8, frame: Self.frame($0.element)) },
                              target: Self.frame(target))
        #expect(trace.readout == readout)
    }
}
