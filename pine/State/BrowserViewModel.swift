import Combine
import Foundation

final class BrowserViewModel: ObservableObject {
    @Published var tabs: [Tab]
    @Published var selectedTabID: UUID?

    init() {
        let firstTab = Tab(urlString: "https://example.com")
        tabs = [firstTab]
        selectedTabID = firstTab.id
    }

    func newTab(urlString: String = "https://example.com") {
        let tab = Tab(urlString: urlString)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func closeTab(id: UUID) {
        tabs.removeAll { $0.id == id }

        guard !tabs.isEmpty else {
            selectedTabID = nil
            return
        }

        if selectedTabID == id {
            selectedTabID = tabs[0].id
        } else if let selectedTabID, tabs.contains(where: { $0.id == selectedTabID }) {
            self.selectedTabID = selectedTabID
        } else {
            selectedTabID = tabs[0].id
        }
    }

    func selectTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }
}
