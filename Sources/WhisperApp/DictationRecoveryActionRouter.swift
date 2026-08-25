import Foundation

@MainActor
final class DictationRecoveryActionRouter {
    typealias AsyncAction = @MainActor () async -> Void
    typealias FeatureActiveAction = @MainActor (Bool) async -> Void

    private let onRetry: AsyncAction
    private let onDiscard: AsyncAction
    private let setFeatureActive: FeatureActiveAction
    private var actionTask: Task<Void, Never>?
    private var actionID: UUID?

    var isRunning: Bool {
        actionTask != nil
    }

    init(
        onRetry: @escaping AsyncAction,
        onDiscard: @escaping AsyncAction,
        setFeatureActive: @escaping FeatureActiveAction
    ) {
        self.onRetry = onRetry
        self.onDiscard = onDiscard
        self.setFeatureActive = setFeatureActive
    }

    func scheduleRetry() {
        schedule { [onRetry, setFeatureActive] in
            await setFeatureActive(true)
            await onRetry()
            await setFeatureActive(false)
        }
    }

    func scheduleDiscard() {
        schedule { [onDiscard, setFeatureActive] in
            await onDiscard()
            await setFeatureActive(false)
        }
    }

    func stop() {
        actionTask?.cancel()
        actionTask = nil
        actionID = nil
    }

    private func schedule(_ action: @escaping AsyncAction) {
        guard actionTask == nil else { return }
        let id = UUID()
        actionID = id
        actionTask = Task { [weak self] in
            await action()
            self?.didComplete(id: id)
        }
    }

    private func didComplete(id: UUID) {
        guard actionID == id else { return }
        actionTask = nil
        actionID = nil
    }
}
