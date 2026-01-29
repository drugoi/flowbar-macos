import Foundation

enum BatchURLParser {
    static func parse(_ raw: String) -> [String] {
        raw
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
