import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var playbackController: PlaybackController
    @ObservedObject var downloadManager: DownloadManager

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: FocusField?

    @StateObject private var networkMonitor = NetworkMonitor()

    @State private var searchText = ""
    @State private var newURL = ""
    @State private var newDisplayName = ""
    @State private var validationError: String?
    @State private var ytdlpMissing = false
    @State private var showClearDownloadsConfirm = false
    @State private var deleteCandidate: Track?
    @State private var globalErrorMessage: String?
    @State private var failedTrack: Track?
    @State private var renameCandidate: Track?
    @State private var renameText: String = ""

    private enum FocusField {
        case search
        case url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !networkMonitor.isOnline {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You're offline")
                        .font(.headline)
                    Text("Check your internet connection to download audio.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Copy Diagnostics") {
                        copyDiagnostics()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            if ytdlpMissing {
                VStack(alignment: .leading, spacing: 4) {
                    Text("yt-dlp not found")
                        .font(.headline)
                    Text("Install with: brew install yt-dlp")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Copy Install Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install yt-dlp", forType: .string)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            if let globalErrorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Download issue")
                        .font(.headline)
                    Text(globalErrorMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        if let failedTrack {
                            Button("Retry") {
                                resolveAndDownload(failedTrack)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button("Logs") {
                            copyDiagnostics()
                        }
                        Button("Dismiss") {
                            self.globalErrorMessage = nil
                            self.failedTrack = nil
                        }
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            nowPlayingSection
            searchSection
            trackListSection
            addNewSection
            utilitiesSection
        }
        .padding(12)
        .onAppear {
            libraryStore.load()
            playbackController.positionUpdateHandler = { [weak libraryStore, weak playbackController] time in
                guard let trackId = playbackController?.currentTrack?.id else { return }
                DispatchQueue.main.async {
                    libraryStore?.updatePlaybackPosition(trackId: trackId, position: time)
                }
            }
            Task.detached {
                let available = YtDlpClient().isAvailable()
                await MainActor.run {
                    ytdlpMissing = !available
                }
            }
            DispatchQueue.main.async {
                focusedField = .search
            }
        }
        .onExitCommand {
            dismiss()
        }
        .alert("Clear all downloads?", isPresented: $showClearDownloadsConfirm) {
            Button("Clear Downloads", role: .destructive) {
                libraryStore.clearDownloads()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all cached audio files.")
        }
        .alert("Delete track?", isPresented: Binding(get: {
            deleteCandidate != nil
        }, set: { newValue in
            if !newValue { deleteCandidate = nil }
        })) {
            Button("Delete", role: .destructive) {
                if let track = deleteCandidate {
                    libraryStore.removeTrack(track)
                }
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            Text("This removes the track and any downloaded audio.")
        }
        .alert("Rename track", isPresented: Binding(get: {
            renameCandidate != nil
        }, set: { newValue in
            if !newValue { renameCandidate = nil }
        })) {
            TextField("Display name", text: $renameText)
            Button("Save") {
                guard var track = renameCandidate else { return }
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                track.displayName = trimmed
                libraryStore.updateTrack(track)
                renameCandidate = nil
            }
            Button("Cancel", role: .cancel) {
                renameCandidate = nil
            }
        } message: {
            Text("Update the track display name.")
        }
    }

    private var nowPlayingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Now Playing")
                .font(.headline)
            Text(playbackController.currentTrack?.displayName ?? "Nothing yet")
                .lineLimit(2)
            HStack(spacing: 8) {
                Button(playbackController.state == .playing ? "Pause" : "Play") {
                    if playbackController.state == .playing {
                        playbackController.pause()
                    } else {
                        playbackController.resume()
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityLabel(playbackController.state == .playing ? "Pause playback" : "Resume playback")
                Button("Stop") {
                    playbackController.stop()
                }
                .accessibilityLabel("Stop playback")
            }
            .disabled(playbackController.currentTrack == nil)
            Text(statusLine)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var statusLine: String {
        if let activeId = downloadManager.activeTrackId {
            let percentage = Int((downloadManager.progress ?? 0) * 100)
            return "Downloading \(percentage)%"
        }
        switch playbackController.state {
        case .idle:
            return "Idle"
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .error:
            return "Error"
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Search")
                .font(.headline)
            TextField("Search tracks", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .search)
                .accessibilityLabel("Search tracks")
        }
    }

    private var trackListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tracks")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !filteredFeatured.isEmpty {
                        Text("Featured")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        ForEach(filteredFeatured) { track in
                            TrackRow(
                                track: track,
                                progress: progressText(for: track),
                                downloadDisabled: downloadManager.activeTrackId != nil && downloadManager.activeTrackId != track.id,
                                isUserTrack: false,
                                onPlay: { play(track) },
                                onDownload: { resolveAndDownload(track) },
                                onRetry: { resolveAndDownload(track) },
                                onCancel: { cancelDownload(for: track) },
                                onRemoveDownload: { libraryStore.removeDownload(for: track) },
                                onDiagnostics: { copyDiagnostics() },
                                onDelete: nil,
                                onRename: nil
                            )
                        }
                    }
                    if !filteredLibrary.isEmpty {
                        Text("My Library")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        ForEach(filteredLibrary) { track in
                            TrackRow(
                                track: track,
                                progress: progressText(for: track),
                                downloadDisabled: downloadManager.activeTrackId != nil && downloadManager.activeTrackId != track.id,
                                isUserTrack: true,
                                onPlay: { play(track) },
                                onDownload: { resolveAndDownload(track) },
                                onRetry: { resolveAndDownload(track) },
                                onCancel: { cancelDownload(for: track) },
                                onRemoveDownload: { libraryStore.removeDownload(for: track) },
                                onDiagnostics: { copyDiagnostics() },
                                onDelete: { deleteCandidate = track },
                                onRename: { beginRename(track) }
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private var addNewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add New")
                .font(.headline)
            TextField("YouTube URL", text: $newURL)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    addNewTrack()
                }
                .focused($focusedField, equals: .url)
                .accessibilityLabel("YouTube URL")
            TextField("Display name (optional)", text: $newDisplayName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    addNewTrack()
                }
                .accessibilityLabel("Display name")
            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Button("Add") {
                addNewTrack()
            }
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityLabel("Add track")
        }
    }

    private var utilitiesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Utilities")
                .font(.headline)
            if let lastError = libraryStore.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Button("Clear Downloads") {
                showClearDownloadsConfirm = true
            }
            .accessibilityLabel("Clear all downloads")
            Button("Copy Diagnostics") {
                copyDiagnostics()
            }
            .accessibilityLabel("Copy diagnostics")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .accessibilityLabel("Quit LongPlay")
        }
    }

    private func addNewTrack() {
        validationError = nil
        switch URLValidator.validate(newURL) {
        case .failure(let error):
            validationError = error.localizedDescription
            DiagnosticsLogger.shared.log(level: "warning", message: "URL validation failed: \(error.localizedDescription)")
        case .success(let validated):
            let name = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? validated.videoId : name
            var track = Track.makeNew(
                sourceURL: validated.canonicalURL,
                videoId: validated.videoId,
                displayName: displayName
            )
            track.downloadState = .resolving
            libraryStore.addToLibrary(track)
            DiagnosticsLogger.shared.log(level: "info", message: "Added track \(validated.videoId)")
            newURL = ""
            newDisplayName = ""
            resolveAndDownload(track)
        }
    }

    private var filteredFeatured: [Track] {
        filter(tracks: libraryStore.library.featured)
    }

    private var filteredLibrary: [Track] {
        filter(tracks: libraryStore.library.userLibrary)
    }

    private func filter(tracks: [Track]) -> [Track] {
        guard !searchText.isEmpty else { return tracks }
        let needle = searchText.lowercased()
        return tracks.filter { track in
            track.displayName.lowercased().contains(needle)
                || (track.resolvedTitle?.lowercased().contains(needle) ?? false)
        }
    }

    private func resolveAndDownload(_ track: Track) {
        Task {
            guard networkMonitor.isOnline else {
                var failed = track
                failed.downloadState = .failed
                failed.lastError = "No internet connection."
                libraryStore.updateTrack(failed)
                globalErrorMessage = "No internet connection."
                failedTrack = failed
                DiagnosticsLogger.shared.log(level: "warning", message: "Download blocked: offline")
                return
            }
            if let activeId = downloadManager.activeTrackId, activeId != track.id {
                DiagnosticsLogger.shared.log(level: "warning", message: "Download already in progress.")
                return
            }
            do {
                globalErrorMessage = nil
                failedTrack = nil

                var resolving = track
                resolving.downloadState = .resolving
                resolving.lastError = nil
                libraryStore.updateTrack(resolving)

                let resolved = try await MetadataResolver.resolve(for: track.sourceURL)
                var updated = resolving
                updated.resolvedTitle = resolved.title
                updated.durationSeconds = resolved.durationSeconds
                updated.downloadState = .downloading
                updated.lastError = nil
                libraryStore.updateTrack(updated)

                let fileURL = try await downloadManager.startDownload(for: updated)
                updated.downloadState = .downloaded
                updated.downloadProgress = 1.0
                updated.localFilePath = fileURL.path
                libraryStore.updateTrack(updated)
            } catch {
                var failed = track
                failed.downloadState = .failed
                failed.lastError = error.localizedDescription
                libraryStore.updateTrack(failed)
                DiagnosticsLogger.shared.log(level: "error", message: "Download failed: \(error.localizedDescription)")
                globalErrorMessage = error.localizedDescription
                failedTrack = failed
            }
        }
    }

    private func play(_ track: Track) {
        guard let path = track.localFilePath else { return }
        guard FileManager.default.fileExists(atPath: path) else {
            var failed = track
            failed.downloadState = .failed
            failed.lastError = "Local file missing. Re-download required."
            libraryStore.updateTrack(failed)
            globalErrorMessage = "Playback failed. Local file is missing."
            failedTrack = failed
            DiagnosticsLogger.shared.log(level: "error", message: "Playback file missing for \(track.videoId)")
            return
        }
        let url = URL(fileURLWithPath: path)
        do {
            try playbackController.loadAndPlay(track: track, fileURL: url, startAt: track.playbackPositionSeconds)
        } catch {
            var failed = track
            failed.downloadState = .failed
            failed.lastError = "Playback failed. Try re-downloading."
            libraryStore.updateTrack(failed)
            globalErrorMessage = error.localizedDescription
            failedTrack = failed
            DiagnosticsLogger.shared.log(level: "error", message: "Playback failed for \(track.videoId): \(error.localizedDescription)")
        }
    }

    private func cancelDownload(for track: Track) {
        guard downloadManager.activeTrackId == track.id else { return }
        downloadManager.cancelDownload()
        var updated = track
        updated.downloadState = .notDownloaded
        updated.downloadProgress = nil
        updated.lastError = "Download cancelled."
        libraryStore.updateTrack(updated)
        DiagnosticsLogger.shared.log(level: "info", message: "Download cancelled for \(track.videoId)")
    }

    private func beginRename(_ track: Track) {
        renameCandidate = track
        renameText = track.displayName
    }

    private func copyDiagnostics() {
        let diagnostics = DiagnosticsLogger.shared.formattedDiagnostics()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
        DiagnosticsLogger.shared.log(level: "info", message: "Diagnostics copied to clipboard")
    }

    private func progressText(for track: Track) -> String? {
        if downloadManager.activeTrackId == track.id {
            let percentage = Int((downloadManager.progress ?? 0) * 100)
            return "Downloading \(percentage)%"
        }
        if track.downloadState == .resolving {
            return "Resolving metadata..."
        }
        if track.downloadState == .failed, let error = track.lastError {
            return error
        }
        if track.downloadState == .downloaded {
            return "Ready offline"
        }
        return nil
    }
}

private struct TrackRow: View {
    let track: Track
    let progress: String?
    let downloadDisabled: Bool
    let isUserTrack: Bool
    let onPlay: () -> Void
    let onDownload: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onRemoveDownload: () -> Void
    let onDiagnostics: () -> Void
    let onDelete: (() -> Void)?
    let onRename: (() -> Void)?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayName)
                    .font(.body)
                if let resolvedTitle = track.resolvedTitle, resolvedTitle != track.displayName {
                    Text(resolvedTitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let progress {
                    Text(progress)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                if track.downloadState == .downloaded {
                    Button("Play", action: onPlay)
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Play track")
                    Button("Remove", action: onRemoveDownload)
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Remove download")
                } else if track.downloadState == .downloading {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Cancel download")
                } else if track.downloadState == .failed {
                    Button("Retry", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Retry download")
                    Button("Logs", action: onDiagnostics)
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Copy diagnostics")
                } else {
                    Button("Download", action: onDownload)
                        .buttonStyle(.borderedProminent)
                        .disabled(downloadDisabled)
                        .accessibilityLabel("Download track")
                }
                if isUserTrack, let onDelete {
                    if let onRename {
                        Button("Rename", action: onRename)
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Rename track")
                    }
                    Button("Delete", action: onDelete)
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Delete track")
                }
            }
        }
        .padding(6)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            switch track.downloadState {
            case .downloaded:
                onPlay()
            case .downloading, .resolving:
                break
            default:
                onDownload()
            }
        }
    }
}
