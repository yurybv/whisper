import Foundation

enum SidebarDestination: String, CaseIterable, Identifiable {
    case home = "Home"
    case modes = "Modes"
    case recordings = "Recordings"
    case history = "History"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .modes: "slider.horizontal.3"
        case .recordings: "record.circle"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}
