import Foundation

extension String {
    /// Truncate to maxLength characters, appending ellipsis if needed
    func truncated(maxLength: Int = 200) -> String {
        if count <= maxLength { return self }
        return String(prefix(maxLength)) + "…"
    }

    /// Get the first line of a multi-line string
    var firstLine: String {
        components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? self
    }
}
