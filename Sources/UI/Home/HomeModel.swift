import Observation

enum HomeReadiness {
    static func title(microphone: PermissionState, apiKey: APIKeySettingsState) -> String {
        guard microphone == .granted else { return "Dictation needs microphone access" }
        switch apiKey {
        case .missing:
            return "Dictation needs an OpenAI API key"
        case .failed:
            return "OpenAI connection needs attention"
        case .testing:
            return "Checking OpenAI connection"
        case .saved, .connected:
            return "Ready to dictate"
        }
    }

    static func subtitle(permissions: PermissionSnapshot, apiKey: APIKeySettingsState) -> String {
        guard permissions.microphone == .granted,
              apiKey == .saved || apiKey == .connected else {
            return "Finish setup in Settings before starting dictation."
        }
        guard permissions.accessibility == .granted,
              permissions.inputMonitoring == .granted else {
            return "Dictation is ready here. Grant keyboard permissions for global shortcuts and direct insertion."
        }
        return "Whisper is ready from the menu bar or any application."
    }
}

@MainActor
@Observable
final class HomeModel {
    private let historyRepository: HistoryRepository

    private(set) var recentHistory: [RecentHistoryItem] = []
    private(set) var errorMessage: String?

    init(historyRepository: HistoryRepository) {
        self.historyRepository = historyRepository
    }

    func refresh() {
        do {
            recentHistory = try historyRepository.recentHistory(limit: 5)
            errorMessage = nil
        } catch {
            recentHistory = []
            errorMessage = "Recent history could not be loaded."
        }
    }
}
