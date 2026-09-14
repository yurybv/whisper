import Foundation

struct MeetingRecoveryService: Sendable {
    typealias ProcessingAvailable = @Sendable () async -> Bool

    private let history: any MeetingJobStore
    private let coordinator: MeetingProcessingCoordinator
    private let processingAvailable: ProcessingAvailable

    init(
        history: any MeetingJobStore,
        coordinator: MeetingProcessingCoordinator,
        processingAvailable: @escaping ProcessingAvailable
    ) {
        self.history = history
        self.coordinator = coordinator
        self.processingAvailable = processingAvailable
    }

    func resumeIncompleteJobs() async throws {
        let meetings = try await history.incompleteMeetings()
        for meeting in meetings where meeting.status == .recording || meeting.status == .finalizing {
            await coordinator.resume(meetingID: meeting.id)
        }
        guard await processingAvailable() else { return }
        for meeting in meetings where meeting.status == .captured
            || meeting.status == .transcribing
            || meeting.status == .processing {
            await coordinator.resume(meetingID: meeting.id)
        }
    }
}
