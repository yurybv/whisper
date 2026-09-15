import Foundation

enum HistoryTextExporter {
    static func resultText(for entry: HistoryEntry) -> String? {
        let value: String
        switch entry.content {
        case let .dictation(dictation): value = dictation.outputText
        case let .recording(meeting, _): value = meeting.processedText
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func text(for entry: HistoryEntry) -> String {
        switch entry.content {
        case let .dictation(dictation):
            return [
                "Whisper Dictation",
                "Date: \(date(dictation.createdAt))",
                "Mode: \(dictation.modeNameSnapshot)",
                "",
                "Original Transcript",
                content(dictation.originalText),
                "",
                "Processed Result",
                content(dictation.outputText),
            ].joined(separator: "\n") + "\n"
        case let .recording(meeting, segments):
            var lines = [
                "Whisper Recording",
                "Title: \(meeting.title)",
                "Date: \(date(meeting.startedAt))",
                "Duration: \(timestamp(meeting.duration))",
                "",
                "Transcript",
            ]
            if segments.isEmpty {
                lines.append("No transcript available.")
            } else {
                lines.append(contentsOf: segments.map { segment in
                    let speaker = segment.source == .you ? "You" : "Others"
                    return "[\(timestamp(segment.startTime))] \(speaker): \(segment.text)"
                })
            }
            lines += ["", "Processed Result", content(meeting.processedText)]
            return lines.joined(separator: "\n") + "\n"
        }
    }

    static func export(_ entry: HistoryEntry, to destination: URL) throws {
        try text(for: entry).write(to: destination, atomically: true, encoding: .utf8)
    }

    static func suggestedFilename(for entry: HistoryEntry) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let replaced = entry.title.unicodeScalars.map { invalid.contains($0) ? " " : String($0) }.joined()
        let compact = replaced.split(whereSeparator: \ .isWhitespace).joined(separator: " ")
        let base = compact.isEmpty ? "Whisper Export" : String(compact.prefix(80))
        return "\(base).txt"
    }

    private static func content(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not available." : trimmed
    }

    private static func date(_ value: Date) -> String {
        value.ISO8601Format(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.colon))
    }

    private static func timestamp(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        if seconds >= 3_600 {
            return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
