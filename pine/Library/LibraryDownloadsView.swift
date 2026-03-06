import SwiftUI

struct LibraryDownloadsView: View {
    @ObservedObject private var downloadManager = SharedStores.shared.downloadManager
    @State private var searchText = ""

    var body: some View {
        List(filteredItems) { item in
            LibraryDownloadRowView(downloadManager: downloadManager, item: item)
        }
        .overlay {
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Downloads Yet" : "No Matching Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text(
                        searchText.isEmpty
                        ? "Downloads will appear here."
                        : "Try a different search term."
                    )
                )
            }
        }
        .searchable(text: $searchText, prompt: "Search downloads")
        .navigationTitle("Downloads")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear Completed") {
                    downloadManager.clearCompleted()
                }
                .disabled(!downloadManager.items.contains(where: { $0.status == .completed }))
            }
        }
    }

    private var filteredItems: [DownloadItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return downloadManager.items }

        return downloadManager.items.filter { item in
            item.filename.lowercased().contains(query)
                || item.sourceURL?.absoluteString.lowercased().contains(query) == true
                || item.destination?.path.lowercased().contains(query) == true
        }
    }
}

private struct LibraryDownloadRowView: View {
    @ObservedObject var downloadManager: DownloadManager
    let item: DownloadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(item.filename)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(item.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: item.progress)
                .frame(maxWidth: .infinity)

            if let destination = item.destination {
                Text(destination.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let errorDescription = item.errorDescription, !errorDescription.isEmpty {
                Text(errorDescription)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                if downloadManager.canPause(item) {
                    Button("Pause") {
                        downloadManager.pause(itemID: item.id)
                    }
                } else if downloadManager.canResume(item) {
                    Button("Resume") {
                        downloadManager.resume(itemID: item.id)
                    }
                }

                if downloadManager.canCancel(item) {
                    Button("Cancel") {
                        downloadManager.cancel(itemID: item.id)
                    }
                }

                Button("Open") {
                    downloadManager.openFile(itemID: item.id)
                }
                .disabled(!downloadManager.canOpen(item))

                Button("Reveal") {
                    downloadManager.revealInFinder(itemID: item.id)
                }
                .disabled(!downloadManager.canReveal(item))

                Button("Retry") {
                    downloadManager.retry(itemID: item.id)
                }
                .disabled(!downloadManager.canRetry(item))
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
