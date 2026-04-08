import Foundation

enum SearchMode: String, CaseIterable, Codable {
    case exact = "Exact"
    case fuzzy = "Fuzzy"
    case regex = "Regex"
    case mixed = "Mixed"
}

struct SearchResult: Identifiable {
    let item: ClipboardItem
    let score: Double  // 0.0 = perfect match, 1.0 = worst match
    let matchedRanges: [Range<String.Index>]

    var id: UUID { item.id }
}

struct SearchEngine {

    func search(query: String, in items: [ClipboardItem], mode: SearchMode) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return items.map { SearchResult(item: $0, score: 0, matchedRanges: []) }
        }

        switch mode {
        case .exact:
            return exactSearch(trimmed, items)
        case .fuzzy:
            return fuzzySearch(trimmed, items)
        case .regex:
            return regexSearch(trimmed, items)
        case .mixed:
            let exact = exactSearch(trimmed, items)
            return exact.isEmpty ? fuzzySearch(trimmed, items) : exact
        }
    }

    // MARK: - Exact Search

    private func exactSearch(_ query: String, _ items: [ClipboardItem]) -> [SearchResult] {
        items.compactMap { item -> SearchResult? in
            let text = item.title
            guard let range = text.range(of: query, options: .caseInsensitive) else {
                return nil
            }
            return SearchResult(item: item, score: 0, matchedRanges: [range])
        }
    }

    // MARK: - Fuzzy Search

    private func fuzzySearch(_ query: String, _ items: [ClipboardItem]) -> [SearchResult] {
        let queryLower = query.lowercased()

        return items.compactMap { item -> SearchResult? in
            let text = item.title.lowercased()
            let (matches, score) = fuzzyMatch(pattern: queryLower, text: text)
            guard matches else { return nil }
            return SearchResult(item: item, score: score, matchedRanges: [])
        }
        .sorted { $0.score < $1.score }
    }

    /// Simple fuzzy matching: all characters of pattern must appear in order in text
    private func fuzzyMatch(pattern: String, text: String) -> (Bool, Double) {
        var patternIndex = pattern.startIndex
        var textIndex = text.startIndex
        var matchCount = 0
        var gaps = 0
        var lastMatchIndex: String.Index?

        while patternIndex < pattern.endIndex && textIndex < text.endIndex {
            if pattern[patternIndex] == text[textIndex] {
                if let last = lastMatchIndex, text.distance(from: last, to: textIndex) > 1 {
                    gaps += text.distance(from: last, to: textIndex) - 1
                }
                lastMatchIndex = textIndex
                matchCount += 1
                patternIndex = pattern.index(after: patternIndex)
            }
            textIndex = text.index(after: textIndex)
        }

        let matched = patternIndex == pattern.endIndex
        guard matched else { return (false, 1.0) }

        // Score: lower is better. Penalize gaps and text length difference.
        let lengthDiff = Double(text.count - pattern.count)
        let score = (Double(gaps) + lengthDiff * 0.1) / Double(text.count + 1)
        return (true, min(score, 1.0))
    }

    // MARK: - Regex Search

    private func regexSearch(_ query: String, _ items: [ClipboardItem]) -> [SearchResult] {
        // Limit pattern length to prevent ReDoS
        guard query.count <= 500,
              let regex = try? NSRegularExpression(pattern: query, options: .caseInsensitive)
        else {
            return []
        }

        return items.compactMap { item -> SearchResult? in
            let text = item.title
            let nsRange = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: nsRange),
                  let range = Range(match.range, in: text)
            else {
                return nil
            }
            return SearchResult(item: item, score: 0, matchedRanges: [range])
        }
    }
}
