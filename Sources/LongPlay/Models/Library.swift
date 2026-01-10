import Foundation

struct Library: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var featuredLibrary: [Track] = []
    var userLibrary: [Track]

    init(schemaVersion: Int = Library.currentSchemaVersion,
         featuredLibrary: [Track] = [],
         userLibrary: [Track]) {
        self.schemaVersion = schemaVersion
        self.featuredLibrary = featuredLibrary
        self.userLibrary = userLibrary
    }
}
