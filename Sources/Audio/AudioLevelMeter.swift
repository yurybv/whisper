import Foundation

struct AudioLevelMeter: Sendable {
    let smoothingFactor: Float
    private(set) var level: Float = 0

    init(smoothingFactor: Float = 0.2) {
        self.smoothingFactor = min(max(smoothingFactor, 0), 1)
    }

    mutating func process(samples: [Float]) -> Float {
        let current = Self.normalizedRMS(samples: samples)
        level += smoothingFactor * (current - level)
        return level
    }

    static func normalizedRMS(samples: [Float]) -> Float {
        guard !samples.isEmpty else {
            return 0
        }
        let meanSquare = samples.reduce(Float.zero) { partialResult, sample in
            let clamped = min(max(sample, -1), 1)
            return partialResult + (clamped * clamped)
        } / Float(samples.count)
        return min(max(sqrt(meanSquare), 0), 1)
    }
}
