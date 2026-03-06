import Combine
import Foundation

@MainActor
final class CommandPaletteViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [PaletteItem] = []
    @Published var selectedIndex = 0

    private let browserViewModel: BrowserViewModel
    private var cancellables: Set<AnyCancellable> = []

    init(browserViewModel: BrowserViewModel) {
        self.browserViewModel = browserViewModel
        bind()
    }

    var isPresented: Bool {
        browserViewModel.store.isCommandPalettePresented
    }

    func open() {
        browserViewModel.store.isCommandPalettePresented = true
        refreshResults()
    }

    func close() {
        browserViewModel.store.isCommandPalettePresented = false
        query = ""
        results = []
        selectedIndex = 0
    }

    func toggle() {
        isPresented ? close() : open()
    }

    func moveSelectionUp() {
        guard !results.isEmpty else { return }
        selectedIndex = selectedIndex == 0 ? (results.count - 1) : (selectedIndex - 1)
    }

    func moveSelectionDown() {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % results.count
    }

    func executeSelectedItem(openInNewTab: Bool = false) {
        guard !results.isEmpty else { return }
        guard selectedIndex >= 0, selectedIndex < results.count else { return }
        execute(item: results[selectedIndex], openInNewTab: openInNewTab)
    }

    func execute(item: PaletteItem, openInNewTab: Bool = false) {
        browserViewModel.executePaletteItem(item, openInNewTab: openInNewTab)
        close()
    }

    func groupedResults(for kind: PaletteItemKind) -> [PaletteItem] {
        results.filter { $0.kind == kind }
    }

    func indexOfResult(withID id: String) -> Int? {
        results.firstIndex(where: { $0.id == id })
    }

    private func bind() {
        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshResults()
            }
            .store(in: &cancellables)

        browserViewModel.store.$tabs
            .sink { [weak self] _ in
                self?.refreshResultsIfNeeded()
            }
            .store(in: &cancellables)

        browserViewModel.historyStore.$entries
            .sink { [weak self] _ in
                self?.refreshResultsIfNeeded()
            }
            .store(in: &cancellables)

        browserViewModel.bookmarksStore.$bookmarks
            .sink { [weak self] _ in
                self?.refreshResultsIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func refreshResultsIfNeeded() {
        guard isPresented else { return }
        refreshResults()
    }

    private func refreshResults() {
        guard isPresented else { return }

        let tabs = searchTabs(query: query)
        let history = searchHistory(query: query)
        let bookmarks = searchBookmarks(query: query)
        let commands = browserViewModel.searchPaletteCommands(query: query)

        results = tabs + history + bookmarks + commands

        if results.isEmpty {
            selectedIndex = 0
        } else {
            selectedIndex = min(max(selectedIndex, 0), results.count - 1)
        }
    }

    private func searchTabs(query: String) -> [PaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return browserViewModel.tabs.compactMap { tab in
            let score = bestScore(
                query: trimmed,
                candidates: [tab.title, tab.urlString]
            )
            guard let score else { return nil }
            return PaletteItem(
                id: "tab:\(tab.id.uuidString)",
                kind: .tab,
                title: tab.title,
                subtitle: tab.urlString,
                icon: tab.isPrivate ? "eye.slash" : "globe",
                score: score,
                payload: .tab(
                    PaletteTabPayload(
                        tabID: tab.id,
                        urlString: tab.urlString
                    )
                )
            )
        }
        .sorted(by: sortByScoreAndTitle)
    }

    private func searchHistory(query: String) -> [PaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return browserViewModel.historyStore.entries.compactMap { entry in
            let score = bestScore(
                query: trimmed,
                candidates: [entry.title, entry.urlString]
            )
            guard let score else { return nil }
            return PaletteItem(
                id: "history:\(entry.id.uuidString)",
                kind: .history,
                title: entry.title,
                subtitle: entry.urlString,
                icon: "clock",
                score: score,
                payload: .history(
                    PaletteHistoryPayload(
                        entryID: entry.id,
                        urlString: entry.urlString
                    )
                )
            )
        }
        .sorted(by: sortByScoreAndTitle)
    }

    private func searchBookmarks(query: String) -> [PaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return browserViewModel.bookmarksStore.bookmarks.compactMap { bookmark in
            let score = bestScore(
                query: trimmed,
                candidates: [bookmark.title, bookmark.urlString]
            )
            guard let score else { return nil }
            return PaletteItem(
                id: "bookmark:\(bookmark.id.uuidString)",
                kind: .bookmark,
                title: bookmark.title,
                subtitle: bookmark.urlString,
                icon: "bookmark",
                score: score,
                payload: .bookmark(
                    PaletteBookmarkPayload(
                        bookmarkID: bookmark.id,
                        urlString: bookmark.urlString
                    )
                )
            )
        }
        .sorted(by: sortByScoreAndTitle)
    }

    private func bestScore(query: String, candidates: [String]) -> Int? {
        if query.isEmpty {
            return 0
        }
        return candidates
            .compactMap { FuzzyMatcher.score(query: query, candidate: $0) }
            .max()
    }

    private func sortByScoreAndTitle(lhs: PaletteItem, rhs: PaletteItem) -> Bool {
        if lhs.score == rhs.score {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return lhs.score > rhs.score
    }
}
