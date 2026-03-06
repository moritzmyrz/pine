import Foundation

enum FuzzyMatcher {
    static func score(query: String, candidate: String) -> Int? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return 0
        }

        let queryChars = Array(trimmedQuery.lowercased())
        let candidateChars = Array(candidate.lowercased())
        if queryChars.count > candidateChars.count {
            return nil
        }

        var queryIndex = 0
        var totalScore = 0
        var previousMatchIndex: Int?

        for candidateIndex in candidateChars.indices {
            guard queryIndex < queryChars.count else { break }
            guard candidateChars[candidateIndex] == queryChars[queryIndex] else { continue }

            totalScore += 10

            if let previousMatchIndex {
                let distance = candidateIndex - previousMatchIndex
                if distance == 1 {
                    totalScore += 15
                } else {
                    totalScore -= min(distance, 8)
                }
            }

            if isWordStart(at: candidateIndex, in: candidateChars) {
                totalScore += 20
            }

            previousMatchIndex = candidateIndex
            queryIndex += 1
        }

        guard queryIndex == queryChars.count else {
            return nil
        }

        if candidate.lowercased().hasPrefix(trimmedQuery.lowercased()) {
            totalScore += 40
        }
        if candidate.caseInsensitiveCompare(trimmedQuery) == .orderedSame {
            totalScore += 80
        }

        return max(totalScore, 1)
    }

    private static func isWordStart(at index: Int, in characters: [Character]) -> Bool {
        guard index > 0 else { return true }
        return !isWordCharacter(characters[index - 1])
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
    }
}
