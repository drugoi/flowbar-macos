import Foundation
import Combine

final class LibraryStore: ObservableObject {
    @Published private(set) var library: Library

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        self.library = LibraryStore.makeDefaultLibrary()
    }

    func load() {
        do {
            let url = try AppPaths.libraryFileURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                return
            }
            let data = try Data(contentsOf: url)
            let decoded = try decoder.decode(Library.self, from: data)
            library = decoded
        } catch {
            DiagnosticsLogger.shared.log(level: "error", message: "Failed to load library: \(error)")
        }
    }

    func save() {
        do {
            let url = try AppPaths.libraryFileURL()
            let data = try encoder.encode(library)
            try data.write(to: url, options: [.atomic])
        } catch {
            DiagnosticsLogger.shared.log(level: "error", message: "Failed to save library: \(error)")
        }
    }

    func addToLibrary(_ track: Track) {
        library.userLibrary.append(track)
        save()
    }

    func updateTrack(_ track: Track) {
        if let index = library.userLibrary.firstIndex(where: { $0.id == track.id }) {
            library.userLibrary[index] = track
            save()
        }
    }

    func removeTrack(_ track: Track) {
        library.userLibrary.removeAll { $0.id == track.id }
        save()
    }

    static func makeDefaultLibrary() -> Library {
        let featured: [Track] = [
            Track.makeNew(
                sourceURL: URL(string: "https://www.youtube.com/watch?v=5qap5aO4i9A")!,
                videoId: "5qap5aO4i9A",
                displayName: "Lo-fi beats (featured placeholder)"
            )
        ]
        return Library(featured: featured, userLibrary: [])
    }
}
