import Foundation

enum PaletteItemKind {
    case command
    case tab
    case history
    case bookmark
}

struct PaletteTabPayload {
    let tabID: UUID
    let urlString: String
}

struct PaletteHistoryPayload {
    let entryID: UUID
    let urlString: String
}

struct PaletteBookmarkPayload {
    let bookmarkID: UUID
    let urlString: String
}

enum PaletteItemPayload {
    case command(Command)
    case tab(PaletteTabPayload)
    case history(PaletteHistoryPayload)
    case bookmark(PaletteBookmarkPayload)
}

struct PaletteItem: Identifiable {
    let id: String
    let kind: PaletteItemKind
    let title: String
    let subtitle: String?
    let icon: String?
    let payload: PaletteItemPayload

    private let computedScore: Int
    var score: Int { computedScore }

    init(
        id: String,
        kind: PaletteItemKind,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        score: Int,
        payload: PaletteItemPayload
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.computedScore = score
        self.payload = payload
    }
}
