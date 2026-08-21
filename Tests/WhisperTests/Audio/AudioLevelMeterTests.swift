import XCTest
@testable import Whisper

final class AudioLevelMeterTests: XCTestCase {
    func testSilenceHasNormalizedLevelZero() {
        XCTAssertEqual(AudioLevelMeter.normalizedRMS(samples: Array(repeating: 0, count: 256)), 0)
    }

    func testSineWaveHasStablePositiveLevel() {
        let sampleCount = 1_600
        let samples = (0..<sampleCount).map { index in
            Float(0.5 * sin(2 * .pi * Double(index) / 32))
        }

        let first = AudioLevelMeter.normalizedRMS(samples: samples)
        let second = AudioLevelMeter.normalizedRMS(samples: samples)

        XCTAssertEqual(first, second, accuracy: 0.000_001)
        XCTAssertEqual(first, 0.353_553, accuracy: 0.001)
    }

    func testMeterSmoothsAbruptLevelChanges() {
        var meter = AudioLevelMeter(smoothingFactor: 0.5)

        let loud = meter.process(samples: Array(repeating: 1, count: 32))
        let quieter = meter.process(samples: Array(repeating: 0, count: 32))

        XCTAssertEqual(loud, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(quieter, 0.25, accuracy: 0.000_001)
    }
}
