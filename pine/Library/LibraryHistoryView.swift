import SwiftUI

struct LibraryHistoryView: View {
    @ObservedObject private var historyStore = SharedStores.shared.historyStore
    @State private var searchText = ""

    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
    private let visitDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        List {
            ForEach(groupedEntries) { group in
                Section(group.title) {
                    ForEach(group.entries) { entry in
                        Button {
                            BrowserWindowManager.shared.openURLInFrontmostWindow(entry.urlString)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                        .lineLimit(1)
                                    Text(entry.urlString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                Text(visitDateTimeFormatter.string(from: entry.date))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .overlay {
            if groupedEntries.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Visited pages will appear here.")
                )
            }
        }
        .searchable(text: $searchText, prompt: "Search history")
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Clear") {
                    Button("Clear Last Hour") {
                        clearLastHour()
                    }
                    .disabled(historyStore.entries.isEmpty)

                    Button("Clear Last Day") {
                        clearLastDay()
                    }
                    .disabled(historyStore.entries.isEmpty)

                    Divider()

                    Button("Clear All", role: .destructive) {
                        historyStore.clearAll()
                    }
                    .disabled(historyStore.entries.isEmpty)
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }
        }
    }

    private var filteredEntries: [HistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return historyStore.entries }

        return historyStore.entries.filter { entry in
            entry.title.lowercased().contains(query) || entry.urlString.lowercased().contains(query)
        }
    }

    private var groupedEntries: [HistoryGroup] {
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            calendar.startOfDay(for: entry.date)
        }

        return grouped.keys
            .sorted(by: >)
            .map { date in
                HistoryGroup(
                    day: date,
                    title: title(for: date),
                    entries: grouped[date, default: []]
                )
            }
    }

    private func title(for day: Date) -> String {
        if calendar.isDateInToday(day) {
            return "Today"
        }
        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }
        return dateFormatter.string(from: day)
    }

    private func clearLastHour() {
        guard let cutoff = calendar.date(byAdding: .hour, value: -1, to: Date()) else { return }
        historyStore.clearEntries(since: cutoff)
    }

    private func clearLastDay() {
        guard let cutoff = calendar.date(byAdding: .day, value: -1, to: Date()) else { return }
        historyStore.clearEntries(since: cutoff)
    }
}

private struct HistoryGroup: Identifiable {
    let day: Date
    let title: String
    let entries: [HistoryEntry]

    var id: Date { day }
}
