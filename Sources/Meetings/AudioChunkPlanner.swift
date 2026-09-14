import Foundation

struct AudioChunkRange: Sendable, Codable, Equatable {
    let index: Int
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval {
        max(0, end - start)
    }
}

enum AudioChunkPlanner {
    static func plan(
        duration: TimeInterval,
        chunkDuration: TimeInterval = 1_200,
        overlap: TimeInterval = 1
    ) -> [AudioChunkRange] {
        guard duration > 0,
              chunkDuration > 0,
              overlap >= 0,
              overlap < chunkDuration else {
            return []
        }

        var chunks: [AudioChunkRange] = []
        var nominalStart: TimeInterval = 0
        while nominalStart < duration {
            let index = chunks.count
            chunks.append(
                AudioChunkRange(
                    index: index,
                    start: index == 0 ? 0 : nominalStart - overlap,
                    end: min(duration, nominalStart + chunkDuration)
                )
            )
            nominalStart += chunkDuration
        }
        return chunks
    }
}
