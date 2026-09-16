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
        let processingMeetings = meetings.filter {
            $0.status == .captured || $0.status == .transcribing || $0.status == .processing
        }
        guard !processingMeetings.isEmpty else { return }
        guard await processingAvailable() else { return }
        for meeting in processingMeetings {
            await coordinator.resume(meetingID: meeting.id)
        }
    }
}
