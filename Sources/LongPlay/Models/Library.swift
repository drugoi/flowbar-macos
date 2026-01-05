import Foundation

struct Library: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var userLibrary: [Track]

    init(schemaVersion: Int = Library.currentSchemaVersion,
         userLibrary: [Track]) {
        self.schemaVersion = schemaVersion
        self.userLibrary = userLibrary
    }
}
