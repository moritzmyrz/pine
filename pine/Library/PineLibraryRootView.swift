import SwiftUI

struct PineLibraryRootView: View {
    @StateObject private var navigationState = LibraryNavigationState.shared

    var body: some View {
        NavigationSplitView {
            List(LibrarySection.allCases, selection: selectionBinding) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Pine Library")
        } detail: {
            selectedDetailView
        }
        .frame(minWidth: 900, minHeight: 560)
    }

    @ViewBuilder
    private var selectedDetailView: some View {
        switch navigationState.selectedSection {
        case .settings:
            LibrarySettingsView()
        case .history:
            LibraryHistoryView()
        case .downloads:
            LibraryDownloadsView()
        case .bookmarks:
            LibraryBookmarksView()
        }
    }

    private var selectionBinding: Binding<LibrarySection?> {
        Binding(
            get: { navigationState.selectedSection },
            set: { section in
                guard let section else { return }
                navigationState.open(section)
            }
        )
    }
}

#Preview {
    PineLibraryRootView()
}
