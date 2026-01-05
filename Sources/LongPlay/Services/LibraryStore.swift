import Foundation
import Combine

final class LibraryStore: ObservableObject {
    @Published private(set) var library: Library
    @Published private(set) var lastError: String?

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var pendingSave: DispatchWorkItem?

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        self.library = LibraryStore.makeDefaultLibrary()
        load()
    }

    func load() {
        do {
            let url = try AppPaths.libraryFileURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                return
            }
            let data = try Data(contentsOf: url)
            var decoded = try decoder.decode(Library.self, from: data)
            if decoded.schemaVersion != Library.currentSchemaVersion {
                DiagnosticsLogger.shared.log(level: "info", message: "Upgrading library schema from \(decoded.schemaVersion) to \(Library.currentSchemaVersion).")
                decoded.schemaVersion = Library.currentSchemaVersion
            }
            library = decoded
            lastError = nil
        } catch {
            lastError = "Failed to load library."
            DiagnosticsLogger.shared.log(level: "error", message: "Failed to load library: \(error)")
        }
    }

    func save() {
        do {
            let url = try AppPaths.libraryFileURL()
            let data = try encoder.encode(library)
            try data.write(to: url, options: [.atomic])
            lastError = nil
        } catch {
            lastError = "Failed to save library."
            DiagnosticsLogger.shared.log(level: "error", message: "Failed to save library: \(error)")
        }
    }

    func addToLibrary(_ track: Track) {
        library.userLibrary.append(track)
        save()
    }

    func updateTrack(_ track: Track) {
        guard replace(track: track) else { return }
        save()
    }

    func removeTrack(_ track: Track) {
        library.userLibrary.removeAll { $0.id == track.id }
        save()
    }

    func updatePlaybackPosition(trackId: UUID, position: TimeInterval) {
        guard let track = trackById(trackId) else { return }
        var updated = track
        updated.playbackPositionSeconds = position
        updated.lastPlayedAt = Date()
        guard replace(track: updated) else { return }
        saveDebounced()
    }

    private func saveDebounced() {
        pendingSave?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.save()
        }
        pendingSave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func trackById(_ id: UUID) -> Track? {
        if let track = library.userLibrary.first(where: { $0.id == id }) {
            return track
        }
        if let track = library.featured.first(where: { $0.id == id }) {
            return track
        }
        return nil
    }

    private func replace(track: Track) -> Bool {
        if let index = library.userLibrary.firstIndex(where: { $0.id == track.id }) {
            library.userLibrary[index] = track
            return true
        }
        if let index = library.featured.firstIndex(where: { $0.id == track.id }) {
            library.featured[index] = track
            return true
        }
        return false
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
