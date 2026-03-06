import Foundation

typealias CommandAction = () -> Void

struct Command {
    let id: String
    let title: String
    let subtitle: String?
    let keywords: [String]
    let shortcutHint: String?
    let group: String
    let action: CommandAction

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        keywords: [String] = [],
        shortcutHint: String? = nil,
        group: String = "Commands",
        action: @escaping CommandAction
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.shortcutHint = shortcutHint
        self.group = group
        self.action = action
    }
}
