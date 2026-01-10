import Foundation
import Combine

final class LibraryStore: ObservableObject {
    @Published private(set) var library: Library
    @Published private(set) var cacheSizeBytes: Int64 = 0
    @Published private(set) var cacheLimitBytes: Int64 = Library.defaultCacheLimitBytes
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
        cacheLimitBytes = library.cacheLimitBytes
        refreshCacheSize()
        enforceCacheLimit(excludingTrackId: nil)
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
            cacheLimitBytes = decoded.cacheLimitBytes
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

    func updateDisplayNameIfDefault(trackId: UUID, defaultName: String, newName: String) {
        guard let track = trackById(trackId) else { return }
        guard track.displayName == defaultName else { return }
        var updated = track
        updated.displayName = newName
        guard replace(track: updated) else { return }
        save()
    }

    func removeTrack(_ track: Track) {
        library.userLibrary.removeAll { $0.id == track.id }
        save()
    }

    func removeDownload(for track: Track) {
        guard let path = track.localFilePath else { return }
        do {
            try FileManager.default.removeItem(atPath: path)
            let updated = resetDownloadState(for: track)
            if replace(track: updated) {
                save()
            }
            refreshCacheSize()
        } catch {
            lastError = "Failed to remove download."
            DiagnosticsLogger.shared.log(level: "error", message: "Failed to remove download: \(error)")
        }
    }

    func clearDownloads() {
        do {
            let cacheDir = try AppPaths.cachesDirectory()
            let contents = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
            for url in contents {
                try FileManager.default.removeItem(at: url)
            }
            library.userLibrary = library.userLibrary.map { track in
                resetDownloadState(for: track)
            }
            save()
            refreshCacheSize()
        } catch {
            lastError = "Failed to clear downloads."
            DiagnosticsLogger.shared.log(level: "error", message: "Failed to clear downloads: \(error)")
        }
    }

    func refreshCacheSize() {
        DispatchQueue.global(qos: .utility).async {
            let size = (try? Self.calculateCacheSize()) ?? 0
            DispatchQueue.main.async {
                self.cacheSizeBytes = size
            }
        }
    }

    private static func calculateCacheSize() throws -> Int64 {
        let cacheDir = try AppPaths.cachesDirectory()
        let files = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey], options: [])
        var total: Int64 = 0
        for file in files {
            let values = try file.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    func updateCacheLimit(bytes: Int64, excludingTrackId: UUID?) {
        let updatedLimit = max(0, bytes)
        cacheLimitBytes = updatedLimit
        library.cacheLimitBytes = updatedLimit
        save()
        enforceCacheLimit(excludingTrackId: excludingTrackId)
    }

    func enforceCacheLimit(excludingTrackId: UUID?) {
        guard cacheLimitBytes > 0 else { return }
        do {
            var currentSize = try Self.calculateCacheSize()
            cacheSizeBytes = currentSize
            guard currentSize > cacheLimitBytes else { return }

            let candidates = library.userLibrary
                .filter { $0.downloadState == .downloaded && $0.id != excludingTrackId }
                .sorted {
                    let lhsDate = $0.lastPlayedAt ?? $0.addedAt
                    let rhsDate = $1.lastPlayedAt ?? $1.addedAt
                    return lhsDate < rhsDate
                }

            var updatedLibrary = library.userLibrary
            for track in candidates {
                guard currentSize > cacheLimitBytes else { break }
                guard let path = track.localFilePath else { continue }
                let fileSize = track.fileSizeBytes ?? Self.readFileSize(atPath: path)
                if FileManager.default.fileExists(atPath: path) {
                    do {
                        try FileManager.default.removeItem(atPath: path)
                    } catch {
                        DiagnosticsLogger.shared.log(level: "error", message: "Failed to evict download: \(error)")
                        continue
                    }
                }
                if let index = updatedLibrary.firstIndex(where: { $0.id == track.id }) {
                    updatedLibrary[index] = resetDownloadState(for: track)
                }
                currentSize = max(0, currentSize - fileSize)
            }
            library.userLibrary = updatedLibrary
            save()
            cacheSizeBytes = currentSize
        } catch {
            lastError = "Failed to enforce cache limit."
            DiagnosticsLogger.shared.log(level: "error", message: "Cache eviction failed: \(error)")
        }
    }

    func updatePlaybackPosition(trackId: UUID, position: TimeInterval) {
        guard let track = trackById(trackId) else { return }
        var updated = track
        updated.playbackPositionSeconds = position
        updated.lastPlayedAt = Date()
        guard replace(track: updated) else { return }
        saveDebounced()
    }

    func resetPlaybackPosition(trackId: UUID) {
        guard let track = trackById(trackId) else { return }
        var updated = track
        updated.playbackPositionSeconds = 0
        updated.lastPlayedAt = Date()
        guard replace(track: updated) else { return }
        save()
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
        return nil
    }

    func track(withId id: UUID) -> Track? {
        trackById(id)
    }

    private func replace(track: Track) -> Bool {
        if let index = library.userLibrary.firstIndex(where: { $0.id == track.id }) {
            library.userLibrary[index] = track
            return true
        }
        return false
    }

    static func makeDefaultLibrary() -> Library {
        return Library(userLibrary: [])
    }

    private func resetDownloadState(for track: Track) -> Track {
        var updated = track
        updated.localFilePath = nil
        updated.fileSizeBytes = nil
        updated.downloadProgress = nil
        updated.downloadState = .notDownloaded
        updated.lastError = nil
        return updated
    }

    private static func readFileSize(atPath path: String) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }
}
