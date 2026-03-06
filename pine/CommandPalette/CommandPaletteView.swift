import AppKit
import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var viewModel: CommandPaletteViewModel
    @FocusState private var isQueryFieldFocused: Bool

    var body: some View {
        if viewModel.isPresented {
            ZStack {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture {
                        viewModel.close()
                    }

                palettePanel
            }
            .transition(.opacity)
            .onAppear {
                isQueryFieldFocused = true
            }
            .onExitCommand {
                viewModel.close()
            }
            .onMoveCommand(perform: handleMoveCommand)
        }
    }

    private var palettePanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search tabs, history, bookmarks, commands", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .focused($isQueryFieldFocused)
                    .onSubmit {
                        viewModel.executeSelectedItem(openInNewTab: shouldOpenInNewTab())
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    section(kind: .tab, title: "Tabs")
                    section(kind: .history, title: "History")
                    section(kind: .bookmark, title: "Bookmarks")
                    section(kind: .command, title: "Commands")
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 360)

            if viewModel.results.isEmpty {
                Divider()
                HStack {
                    Text("No results")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 680)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        .padding(.horizontal, 20)
        .padding(.top, 80)
    }

    @ViewBuilder
    private func section(kind: PaletteItemKind, title: String) -> some View {
        let items = viewModel.groupedResults(for: kind)
        if !items.isEmpty {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 4)

            ForEach(items) { item in
                if let index = viewModel.indexOfResult(withID: item.id) {
                    itemRow(item: item, index: index)
                }
            }
        }
    }

    private func itemRow(item: PaletteItem, index: Int) -> some View {
        Button {
            viewModel.selectedIndex = index
            viewModel.execute(item: item, openInNewTab: shouldOpenInNewTab())
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon ?? fallbackIcon(for: item.kind))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(index == viewModel.selectedIndex ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            viewModel.moveSelectionUp()
        case .down:
            viewModel.moveSelectionDown()
        default:
            break
        }
    }

    private func fallbackIcon(for kind: PaletteItemKind) -> String {
        switch kind {
        case .tab:
            return "square.on.square"
        case .history:
            return "clock"
        case .bookmark:
            return "bookmark"
        case .command:
            return "command"
        }
    }

    private func shouldOpenInNewTab() -> Bool {
        NSEvent.modifierFlags.contains(.option)
    }
}
