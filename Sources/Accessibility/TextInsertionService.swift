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

protocol TextInsertionService: Sendable {
    func captureFocusedTarget() async throws -> FocusedTarget
    func insert(_ text: String, into target: FocusedTarget) async throws -> InsertionResult
}
