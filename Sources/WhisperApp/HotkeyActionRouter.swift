import Foundation

@MainActor
final class HotkeyActionRouter {
    typealias AsyncAction = @MainActor () async -> Void
    typealias AsyncCancelAction = @MainActor () async -> Bool
    typealias Action = @MainActor () -> Void

    private let onBegin: AsyncAction
    private let onFinish: AsyncAction
    private let onChangeMode: Action
    private let onRecordMeeting: Action
    private let onCancel: AsyncCancelAction

    private var finishTask: Task<Void, Never>?
    private var finishTaskID: UUID?

    init(
        onBegin: @escaping AsyncAction,
        onFinish: @escaping AsyncAction,
        onChangeMode: @escaping Action,
        onRecordMeeting: @escaping Action,
        onCancel: @escaping AsyncCancelAction
    ) {
        self.onBegin = onBegin
        self.onFinish = onFinish
        self.onChangeMode = onChangeMode
        self.onRecordMeeting = onRecordMeeting
        self.onCancel = onCancel
    }

    func handle(_ event: HotkeyActionEvent) async {
        switch event {
        case .pressed(.pushToTalk):
            await onBegin()
        case .released(.pushToTalk):
            scheduleFinish()
        case .invoked(.changeMode):
            onChangeMode()
        case .invoked(.recordMeeting):
            onRecordMeeting()
        case .invoked(.cancel):
            guard await onCancel() else { return }
            finishTask?.cancel()
            finishTask = nil
            finishTaskID = nil
        case .pressed, .released, .invoked:
            break
        }
    }

    func scheduleFinish() {
        guard finishTask == nil else { return }
        let taskID = UUID()
        let finish = onFinish
        finishTaskID = taskID
        finishTask = Task { [weak self] in
            await finish()
            guard !Task.isCancelled else { return }
            self?.finishDidComplete(taskID)
        }
    }

    func stop() {
        finishTask?.cancel()
        finishTask = nil
        finishTaskID = nil
    }

    private func finishDidComplete(_ taskID: UUID) {
        guard finishTaskID == taskID else { return }
        finishTask = nil
        finishTaskID = nil
    }
}
