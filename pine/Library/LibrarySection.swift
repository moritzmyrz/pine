import Foundation

enum LibrarySection: String, CaseIterable, Identifiable {
    case settings
    case history
    case downloads
    case bookmarks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings: "Settings"
        case .history: "History"
        case .downloads: "Downloads"
        case .bookmarks: "Bookmarks"
        }
    }

    var systemImage: String {
        switch self {
        case .settings: "gearshape"
        case .history: "clock.arrow.circlepath"
        case .downloads: "arrow.down.circle"
        case .bookmarks: "bookmark"
        }
    }
}
