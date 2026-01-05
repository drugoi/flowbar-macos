import Foundation

struct Library: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var featured: [Track]
    var userLibrary: [Track]

    init(schemaVersion: Int = Library.currentSchemaVersion,
         featured: [Track],
         userLibrary: [Track]) {
        self.schemaVersion = schemaVersion
        self.featured = featured
        self.userLibrary = userLibrary
    }
}
