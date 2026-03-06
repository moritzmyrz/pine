import Combine
import Foundation

@MainActor
final class CommandPaletteViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [PaletteItem] = []
    @Published var selectedIndex = 0

    private let maxResults = 40
    private let shortQueryLength = 2
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

        let previousSelectedID = (selectedIndex >= 0 && selectedIndex < results.count)
            ? results[selectedIndex].id
            : nil
        let mode = parseMode(query: query)

        var merged: [PaletteItem]
        switch mode {
        case let .commandsOnly(commandQuery):
            merged = browserViewModel.searchPaletteCommands(query: commandQuery)
        case let .all(query):
            let isShortQuery = query.count <= shortQueryLength && !query.isEmpty
            let tabs = searchTabs(query: query, isShortQuery: isShortQuery)
            let history = searchHistory(query: query, isShortQuery: isShortQuery)
            let bookmarks = searchBookmarks(query: query, isShortQuery: isShortQuery)
            let commands = browserViewModel.searchPaletteCommands(query: query)
            merged = tabs + history + bookmarks + commands
        }

        results = merged
            .sorted(by: sortByScoreThenKindThenTitle)
            .prefix(maxResults)
            .map { $0 }

        if let previousSelectedID,
           let preservedIndex = results.firstIndex(where: { $0.id == previousSelectedID }) {
            selectedIndex = preservedIndex
            return
        }
        selectedIndex = results.isEmpty ? 0 : min(max(selectedIndex, 0), results.count - 1)
    }

    private func searchTabs(query: String, isShortQuery: Bool) -> [PaletteItem] {
        return browserViewModel.tabs.compactMap { tab in
            let subtitle = tabHost(from: tab.urlString) ?? tab.urlString
            let score = bestScore(
                query: query,
                candidates: [tab.title, subtitle, tab.urlString]
            )
            guard let score else { return nil }

            let adjustedScore = score + prefixBoost(query: query, candidates: [tab.title, subtitle]) + (isShortQuery ? 35 : 0)
            return PaletteItem(
                id: "tab:\(tab.id.uuidString)",
                kind: .tab,
                title: tab.title,
                subtitle: subtitle,
                icon: tab.isPrivate ? "eye.slash" : "globe",
                score: adjustedScore,
                payload: .tab(
                    PaletteTabPayload(
                        tabID: tab.id,
                        urlString: tab.urlString
                    )
                )
            )
        }
    }

    private func searchHistory(query: String, isShortQuery: Bool) -> [PaletteItem] {
        return browserViewModel.historyStore.entries.compactMap { entry in
            let score = bestScore(
                query: query,
                candidates: [entry.title, entry.urlString]
            )
            guard let score else { return nil }
            let adjustedScore = score + prefixBoost(query: query, candidates: [entry.title, entry.urlString]) + (isShortQuery ? -12 : 0)
            return PaletteItem(
                id: "history:\(entry.id.uuidString)",
                kind: .history,
                title: entry.title,
                subtitle: entry.urlString,
                icon: "clock",
                score: adjustedScore,
                payload: .history(
                    PaletteHistoryPayload(
                        entryID: entry.id,
                        urlString: entry.urlString
                    )
                )
            )
        }
    }

    private func searchBookmarks(query: String, isShortQuery: Bool) -> [PaletteItem] {
        return browserViewModel.bookmarksStore.bookmarks.compactMap { bookmark in
            let score = bestScore(
                query: query,
                candidates: [bookmark.title, bookmark.urlString]
            )
            guard let score else { return nil }
            let adjustedScore = score + prefixBoost(query: query, candidates: [bookmark.title, bookmark.urlString]) + (isShortQuery ? -12 : 0)
            return PaletteItem(
                id: "bookmark:\(bookmark.id.uuidString)",
                kind: .bookmark,
                title: bookmark.title,
                subtitle: bookmark.urlString,
                icon: "bookmark",
                score: adjustedScore,
                payload: .bookmark(
                    PaletteBookmarkPayload(
                        bookmarkID: bookmark.id,
                        urlString: bookmark.urlString
                    )
                )
            )
        }
    }

    private func bestScore(query: String, candidates: [String]) -> Int? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return 0
        }
        return candidates
            .compactMap { FuzzyMatcher.score(query: trimmedQuery, candidate: $0) }
            .max()
    }

    private func prefixBoost(query: String, candidates: [String]) -> Int {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else { return 0 }
        let hasPrefixMatch = candidates.contains {
            $0.lowercased().hasPrefix(trimmedQuery)
        }
        return hasPrefixMatch ? 45 : 0
    }

    private func parseMode(query: String) -> SearchMode {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(">") else { return .all(trimmed) }

        let commandQuery = String(trimmed.dropFirst())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .commandsOnly(commandQuery)
    }

    private func tabHost(from urlString: String) -> String? {
        URL(string: urlString)?.host?.lowercased()
    }

    private func sortByScoreThenKindThenTitle(lhs: PaletteItem, rhs: PaletteItem) -> Bool {
        if lhs.score == rhs.score {
            if kindSortPriority(for: lhs.kind) == kindSortPriority(for: rhs.kind) {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return kindSortPriority(for: lhs.kind) < kindSortPriority(for: rhs.kind)
        }
        return lhs.score > rhs.score
    }

    private func kindSortPriority(for kind: PaletteItemKind) -> Int {
        switch kind {
        case .tab:
            return 0
        case .command:
            return 1
        case .history:
            return 2
        case .bookmark:
            return 3
        }
    }
}

private enum SearchMode {
    case all(String)
    case commandsOnly(String)
}
