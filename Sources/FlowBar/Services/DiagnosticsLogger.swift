import Foundation

struct LogEntry: Codable, Equatable {
    let timestamp: Date
    let level: String
    let message: String
}

final class DiagnosticsLogger {
    static let shared = DiagnosticsLogger(maxEntries: 500)

    private let maxEntries: Int
    private let queue = DispatchQueue(label: "flowbar.diagnostics.logger")
    private var entries: [LogEntry] = []

    init(maxEntries: Int) {
        self.maxEntries = maxEntries
    }

    func log(level: String, message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        queue.sync {
            entries.append(entry)
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
        }
    }

    func recentEntries(limit: Int = 200) -> [LogEntry] {
        queue.sync {
            Array(entries.suffix(limit))
        }
    }

    func formattedDiagnostics(limit: Int = 200) -> String {
        let formatter = ISO8601DateFormatter()
        let items = recentEntries(limit: limit)
        guard !items.isEmpty else {
            return "No diagnostics yet."
        }
        return items.map { "\(formatter.string(from: $0.timestamp)) [\($0.level)] \($0.message)" }
            .joined(separator: "\n")
    }
}
