import Foundation

final class CommandRegistry {
    private var commandsByID: [String: Command] = [:]
    private var commandOrder: [String] = []

    init(commands: [Command] = []) {
        register(contentsOf: commands)
    }

    var commands: [Command] {
        commandOrder.compactMap { commandsByID[$0] }
    }

    func register(_ command: Command) {
        if commandsByID[command.id] == nil {
            commandOrder.append(command.id)
        }
        commandsByID[command.id] = command
    }

    func register(contentsOf commands: [Command]) {
        for command in commands {
            register(command)
        }
    }

    func setCommands(_ commands: [Command]) {
        commandsByID.removeAll(keepingCapacity: true)
        commandOrder.removeAll(keepingCapacity: true)
        register(contentsOf: commands)
    }

    func search(query: String) -> [PaletteItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return commands.compactMap { command in
            guard let score = score(command: command, query: trimmedQuery) else {
                return nil
            }

            return PaletteItem(
                id: "command:\(command.id)",
                kind: .command,
                title: command.title,
                subtitle: command.subtitle,
                icon: nil,
                score: score,
                payload: .command(command)
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.score > rhs.score
        }
    }

    private func score(command: Command, query: String) -> Int? {
        if query.isEmpty {
            return 0
        }

        var candidates: [String] = [command.title]
        if let subtitle = command.subtitle, !subtitle.isEmpty {
            candidates.append(subtitle)
        }
        candidates.append(contentsOf: command.keywords)

        var bestScore: Int?
        for candidate in candidates {
            guard let candidateScore = FuzzyMatcher.score(query: query, candidate: candidate) else {
                continue
            }
            bestScore = max(bestScore ?? candidateScore, candidateScore)
        }
        return bestScore
    }
}
