import Combine
import Foundation

final class LibraryNavigationState: ObservableObject {
    static let shared = LibraryNavigationState()

    @Published var selectedSection: LibrarySection = .settings

    private init() {}

    func open(_ section: LibrarySection) {
        selectedSection = section
    }
}
