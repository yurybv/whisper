import Foundation

struct SilenceDetector: Sendable, Equatable {
    let minimumDuration: TimeInterval
    let speechThreshold: Float

    init(minimumDuration: TimeInterval = 0.25, speechThreshold: Float = 0.02) {
        self.minimumDuration = minimumDuration
        self.speechThreshold = speechThreshold
    }

    func containsSpeech(duration: TimeInterval, peakLevel: Float) -> Bool {
        duration >= minimumDuration && peakLevel >= speechThreshold
    }
}
