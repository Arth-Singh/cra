import CoreGraphics
import Foundation

/// One grow as the window server showed it: the window's frame read every few ms off the main
/// thread (which a blocking grow stops). The look check for features.md #2b compares these
/// between the old grow and the new one.
public struct GrowTrace: Equatable, Sendable {
    public struct Sample: Equatable, Sendable {
        /// ms after show() started.
        public let ms: Double
        public let frame: CGRect

        public init(ms: Double, frame: CGRect) {
            self.ms = ms
            self.frame = frame
        }
    }

    public let samples: [Sample]
    /// The frame the window grows to.
    public let target: CGRect

    public init(samples: [Sample], target: CGRect) {
        self.samples = samples
        self.target = target
    }

    public var from: CGRect? { samples.first?.frame }
    /// The last frame the window server showed.
    public var to: CGRect? { samples.last?.frame }

    /// From the last sample at the starting width to the first at the target's width; nil when
    /// the width never changed or never reached the target (the trace ended first).
    public var durationMs: Double? { move.map { $0.end - $0.begin } }

    /// Width progress, 0 at the start and 1 at the end, at 10 %, 20 % … 90 % of the move, each
    /// from the last sample at or before that moment; nil without a move.
    public var curve: [Double]? {
        guard let move, let from else { return nil }
        return (1...9).map { step in
            let t = move.begin + Double(step) / 10 * (move.end - move.begin)
            let width = samples.last { $0.ms <= t }?.frame.width ?? from.width
            return (width - from.width) / (target.width - from.width)
        }
    }

    /// "grow_ms=… grow_from=WxH grow_to=WxH grow_curve=a,b,…", "-" where there is no value.
    public var readout: String {
        let size = { (r: CGRect?) in r.map { "\(Int($0.width.rounded()))x\(Int($0.height.rounded()))" } ?? "-" }
        return "grow_ms=\(durationMs.map { String(format: "%.1f", $0) } ?? "-") grow_from=\(size(from)) grow_to=\(size(to)) "
            + "grow_curve=\(curve.map { $0.map { String(format: "%.2f", $0) }.joined(separator: ",") } ?? "-")"
    }

    private var move: (begin: Double, end: Double)? {
        let half = 0.5
        guard let from, abs(target.width - from.width) > half,
              let first = samples.firstIndex(where: { abs($0.frame.width - from.width) > half }),
              let arrived = samples.firstIndex(where: { abs($0.frame.width - target.width) <= half }) else { return nil }
        let begin = samples[max(0, first - 1)].ms
        return (begin, samples[arrived].ms)
    }
}
