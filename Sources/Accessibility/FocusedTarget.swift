import ApplicationServices
import Foundation

struct FocusedTarget: @unchecked Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let element: AXUIElement?
}

enum InsertionResult: Equatable, Sendable {
    case insertedDirectly
    case pasted
    case copiedForManualPaste
}

enum TextInsertionError: Error, Equatable, Sendable {
    case noFocusedApplication
    case clipboardWriteFailed
}

extension TextInsertionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noFocusedApplication:
            "Whisper could not identify the focused application."
        case .clipboardWriteFailed:
            "Whisper could not copy the dictated text to the clipboard."
        }
    }
}
