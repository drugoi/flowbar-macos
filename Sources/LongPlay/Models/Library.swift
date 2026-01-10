import Foundation

struct Library: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var featured: [Track]
    var userLibrary: [Track]

    init(schemaVersion: Int = Library.currentSchemaVersion,
         featured: [Track] = Library.defaultFeaturedTracks(),
         userLibrary: [Track]) {
        self.schemaVersion = schemaVersion
        self.featured = featured
        self.userLibrary = userLibrary
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case featured
        case userLibrary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Library.currentSchemaVersion
        featured = try container.decodeIfPresent([Track].self, forKey: .featured) ?? Library.defaultFeaturedTracks()
        userLibrary = try container.decodeIfPresent([Track].self, forKey: .userLibrary) ?? []
    }
}

extension Library {
    static func defaultFeaturedTracks() -> [Track] {
        [
            Track.makeNew(
                sourceURL: URL(string: "https://www.youtube.com/watch?v=DWcJFNfaw9c")!,
                videoId: "DWcJFNfaw9c",
                displayName: "Lofi hip hop radio"
            ),
            Track.makeNew(
                sourceURL: URL(string: "https://www.youtube.com/watch?v=lCOF9LN_Zxs")!,
                videoId: "lCOF9LN_Zxs",
                displayName: "Ambient space music"
            ),
            Track.makeNew(
                sourceURL: URL(string: "https://www.youtube.com/watch?v=2OEL4P1Rz04")!,
                videoId: "2OEL4P1Rz04",
                displayName: "Classical focus mix"
            )
        ]
    }
}
