import Foundation

struct Library: Codable, Equatable {
    static let currentSchemaVersion = 2
    static let defaultCacheLimitBytes: Int64 = 5 * 1024 * 1024 * 1024
    static let minimumCacheLimitBytes: Int64 = 1 * 1024 * 1024 * 1024

    var schemaVersion: Int
    var userLibrary: [Track]
    var cacheLimitBytes: Int64

    init(schemaVersion: Int = Library.currentSchemaVersion,
         userLibrary: [Track],
         cacheLimitBytes: Int64 = Library.defaultCacheLimitBytes) {
        self.schemaVersion = schemaVersion
        self.userLibrary = userLibrary
        self.cacheLimitBytes = cacheLimitBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        userLibrary = try container.decodeIfPresent([Track].self, forKey: .userLibrary) ?? []
        cacheLimitBytes = try container.decodeIfPresent(Int64.self, forKey: .cacheLimitBytes) ?? Self.defaultCacheLimitBytes
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case userLibrary
        case cacheLimitBytes
    }
}
