import Foundation

protocol TextInsertionService: Sendable {
    func captureFocusedTarget() async throws -> FocusedTarget
    func insert(_ text: String, into target: FocusedTarget) async throws -> InsertionResult
}
