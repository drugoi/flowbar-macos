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
    @State private var ytdlpVersion: String?
    @State private var ytdlpWarning: String?
    @State private var ffmpegMissing = false
    @State private var selectedTab: Tab = .listen

    private enum FocusField {
        case search
        case url
    }

    private enum Tab: String, CaseIterable, Identifiable {
        case listen = "Listen"
        case add = "Add"
        case utilities = "Utilities"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .listen:
                return "headphones"
            case .add:
                return "plus.circle"
            case .utilities:
                return "gearshape"
            }
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.96, green: 0.96, blue: 0.99),
                         Color(red: 0.92, green: 0.94, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                tabBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !networkMonitor.isOnline {
                            NoticeCard(
                                title: "You're offline",
                                message: "Check your connection to download audio.",
                                actionTitle: "Copy Diagnostics",
                                action: { copyDiagnostics() }
                            )
                        }
                        if ytdlpMissing {
                            NoticeCard(
                                title: "yt-dlp not found",
                                message: "Bundled binary missing. Reinstall or update LongPlay.",
                                actionTitle: "Copy Diagnostics",
                                action: { copyDiagnostics() }
                            )
                        }
                        if ffmpegMissing {
                            NoticeCard(
                                title: "ffmpeg missing",
                                message: "Audio conversion requires ffmpeg. Reinstall or update LongPlay.",
                                actionTitle: "Copy Diagnostics",
                                action: { copyDiagnostics() }
                            )
                        }
                        if let ytdlpWarning {
                            NoticeCard(
                                title: "yt-dlp update recommended",
                                message: ytdlpWarning,
                                actionTitle: "Copy Diagnostics",
                                action: { copyDiagnostics() }
                            )
                        }
                        if let globalErrorMessage {
                            SectionCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(failedTrack == nil ? "Input issue" : "Download issue")
                                        .font(sectionTitleFont)
                                    Text(globalErrorMessage)
                                        .font(.custom("Avenir Next", size: 12))
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 8) {
                                        if let failedTrack, shouldOfferDownloadAnyway(failedTrack) {
                                            Button("Download Anyway") {
                                                downloadOnly(failedTrack)
                                            }
                                            .buttonStyle(PrimaryButtonStyle())
                                        }
                                        if let failedTrack {
                                            Button("Retry") {
                                                resolveAndDownload(failedTrack)
                                            }
                                            .buttonStyle(PrimaryButtonStyle())
                                        }
                                        Button("Logs") {
                                            copyDiagnostics()
                                        }
                                        .buttonStyle(SecondaryButtonStyle())
                                        Button("Dismiss") {
                                            self.globalErrorMessage = nil
                                            self.failedTrack = nil
                                        }
                                        .buttonStyle(SecondaryButtonStyle())
                                    }
                                }
                            }
                        }
                        switch selectedTab {
                        case .listen:
                            nowPlayingSection
                            searchSection
                            trackListSection
                        case .add:
                            addNewSection
                        case .utilities:
                            utilitiesSection
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(14)
        }
        .onAppear {
            libraryStore.load()
            playbackController.positionUpdateHandler = { [weak libraryStore, weak playbackController] time in
                guard let trackId = playbackController?.currentTrack?.id else { return }
                DispatchQueue.main.async {
                    libraryStore?.updatePlaybackPosition(trackId: trackId, position: time)
                }
            }
            Task.detached {
                let client = YtDlpClient()
                let available = client.isAvailable()
                let version = client.fetchVersion()
                let ffmpegAvailable = client.isFfmpegAvailable()
                var warning: String?
                if available, let version, client.isVersionOutdated(version) {
                    warning = "Bundled yt-dlp version \(version) is older than \(YtDlpClient.minimumSupportedVersion)."
                } else if available, version == nil {
                    warning = "Unable to read yt-dlp version. Downloads may fail."
                }
                await MainActor.run {
                    ytdlpMissing = !available
                    ytdlpVersion = version
                    ytdlpWarning = warning
                    ffmpegMissing = !ffmpegAvailable
                }
            }
            DispatchQueue.main.async {
                focusedField = selectedTab == .add ? .url : .search
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

    private var headerRow: some View {
        HStack {
            Text("LongPlay")
                .font(.custom("Avenir Next Demi Bold", size: 16))
            Spacer()
            Text("v0.1")
                .font(.custom("Avenir Next", size: 11))
                .foregroundColor(.secondary)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                    focusedField = tab == .add ? .url : .search
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.custom("Avenir Next Demi Bold", size: 12))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .background(tab == selectedTab ? Color.white : Color.white.opacity(0.6))
                    .foregroundColor(Color(red: 0.18, green: 0.2, blue: 0.25))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(tab == selectedTab ? 0.8 : 0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color.white.opacity(0.5))
        .cornerRadius(12)
    }

    private var nowPlayingSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Now Playing")
                    .font(sectionTitleFont)
                Text(playbackController.currentTrack?.displayName ?? "Nothing yet")
                    .font(.custom("Avenir Next", size: 14))
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
                    .buttonStyle(PrimaryButtonStyle())
                    Button("Stop") {
                        playbackController.stop()
                        if let trackId = playbackController.currentTrack?.id {
                            libraryStore.resetPlaybackPosition(trackId: trackId)
                        }
                    }
                    .accessibilityLabel("Stop playback")
                    .buttonStyle(SecondaryButtonStyle())
                }
                .disabled(playbackController.currentTrack == nil)
                Text(statusLine)
                    .font(.custom("Avenir Next", size: 11))
                    .foregroundColor(.secondary)
            }
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
        SectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Search")
                    .font(sectionTitleFont)
                TextField("Search tracks", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .search)
                    .accessibilityLabel("Search tracks")
                    .accessibilityIdentifier("SearchField")
            }
        }
    }

    private var trackListSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tracks")
                    .font(sectionTitleFont)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !filteredFeatured.isEmpty {
                            Text("Featured")
                                .font(.custom("Avenir Next Demi Bold", size: 12))
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
                                .font(.custom("Avenir Next Demi Bold", size: 12))
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
    }

    private var addNewSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add New")
                    .font(sectionTitleFont)
                TextField("YouTube URL", text: $newURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addNewTrack()
                    }
                    .focused($focusedField, equals: .url)
                    .accessibilityLabel("YouTube URL")
                    .accessibilityIdentifier("URLField")
                TextField("Display name (optional)", text: $newDisplayName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addNewTrack()
                    }
                    .accessibilityLabel("Display name")
                    .accessibilityIdentifier("DisplayNameField")
                if let validationError {
                    Text(validationError)
                        .font(.custom("Avenir Next", size: 11))
                        .foregroundColor(.red)
                }
                Button("Add") {
                    addNewTrack()
                }
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityLabel("Add track")
                .accessibilityIdentifier("AddTrackButton")
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var utilitiesSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Utilities")
                    .font(sectionTitleFont)
                if let lastError = libraryStore.lastError {
                    Text(lastError)
                        .font(.custom("Avenir Next", size: 11))
                        .foregroundColor(.red)
                }
                Button("Clear Downloads") {
                    showClearDownloadsConfirm = true
                }
                .accessibilityLabel("Clear all downloads")
                .buttonStyle(SecondaryButtonStyle())
                Text("Cache: \(formattedBytes(libraryStore.cacheSizeBytes)) • Manual cleanup")
                    .font(.custom("Avenir Next", size: 11))
                    .foregroundColor(.secondary)
                Button("Copy Diagnostics") {
                    copyDiagnostics()
                }
                .accessibilityLabel("Copy diagnostics")
                .buttonStyle(SecondaryButtonStyle())
                Divider()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .accessibilityLabel("Quit LongPlay")
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func addNewTrack() {
        validationError = nil
        switch URLValidator.validate(newURL) {
        case .failure(let error):
            validationError = error.localizedDescription
            globalErrorMessage = error.localizedDescription
            failedTrack = nil
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
            selectedTab = .listen
            focusedField = .search
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
                DiagnosticsLogger.shared.log(level: "info", message: "Resolving metadata for \(track.videoId)")

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
                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let fileSize = attributes[.size] as? NSNumber {
                    updated.fileSizeBytes = fileSize.int64Value
                }
                libraryStore.updateTrack(updated)
                libraryStore.refreshCacheSize()
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

    private func downloadOnly(_ track: Track) {
        Task {
            guard networkMonitor.isOnline else {
                globalErrorMessage = "No internet connection."
                failedTrack = track
                return
            }
            if let activeId = downloadManager.activeTrackId, activeId != track.id {
                DiagnosticsLogger.shared.log(level: "warning", message: "Download already in progress.")
                return
            }
            do {
                globalErrorMessage = nil
                failedTrack = nil
                var updated = track
                updated.downloadState = .downloading
                updated.lastError = nil
                libraryStore.updateTrack(updated)
                let fileURL = try await downloadManager.startDownload(for: updated)
                updated.downloadState = .downloaded
                updated.downloadProgress = 1.0
                updated.localFilePath = fileURL.path
                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let fileSize = attributes[.size] as? NSNumber {
                    updated.fileSizeBytes = fileSize.int64Value
                }
                libraryStore.updateTrack(updated)
                libraryStore.refreshCacheSize()
            } catch {
                var failed = track
                failed.downloadState = .failed
                failed.lastError = error.localizedDescription
                libraryStore.updateTrack(failed)
                globalErrorMessage = error.localizedDescription
                failedTrack = failed
                DiagnosticsLogger.shared.log(level: "error", message: "Download failed: \(error.localizedDescription)")
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

    private func shouldOfferDownloadAnyway(_ track: Track) -> Bool {
        guard let error = track.lastError?.lowercased() else { return false }
        return error.contains("timed out")
    }

    private func copyDiagnostics() {
        let diagnostics = DiagnosticsLogger.shared.formattedDiagnostics()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
        DiagnosticsLogger.shared.log(level: "info", message: "Diagnostics copied to clipboard")
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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
                    .font(.custom("Avenir Next Demi Bold", size: 13))
                if let resolvedTitle = track.resolvedTitle, resolvedTitle != track.displayName {
                    Text(resolvedTitle)
                        .font(.custom("Avenir Next", size: 11))
                        .foregroundColor(.secondary)
                }
                if let progress {
                    Text(progress)
                        .font(.custom("Avenir Next", size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                if track.downloadState == .downloaded {
                    Button("Play", action: onPlay)
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityLabel("Play track")
                    Button("Remove", action: onRemoveDownload)
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityLabel("Remove download")
                } else if track.downloadState == .downloading {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityLabel("Cancel download")
                } else if track.downloadState == .failed {
                    Button("Retry", action: onRetry)
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityLabel("Retry download")
                    Button("Logs", action: onDiagnostics)
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityLabel("Copy diagnostics")
                } else {
                    Button("Download", action: onDownload)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(downloadDisabled)
                        .accessibilityLabel("Download track")
                }
            }
        }
        .padding(6)
        .background(Color.white.opacity(0.7))
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
        .contextMenu {
            if track.downloadState == .downloaded {
                Button("Play", action: onPlay)
                Button("Remove Download", action: onRemoveDownload)
            } else if track.downloadState == .failed {
                Button("Retry Download", action: onRetry)
                Button("Copy Diagnostics", action: onDiagnostics)
            } else if track.downloadState == .downloading {
                Button("Cancel Download", action: onCancel)
            } else {
                Button("Download", action: onDownload)
            }
            if isUserTrack {
                if let onRename {
                    Button("Rename", action: onRename)
                }
                if let onDelete {
                    Button("Delete", role: .destructive, action: onDelete)
                }
            }
        }
    }
}

private struct SectionCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(10)
            .background(Color.white.opacity(0.8))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
            )
    }
}

private struct NoticeCard: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.custom("Avenir Next Demi Bold", size: 13))
                Text(message)
                    .font(.custom("Avenir Next", size: 11))
                    .foregroundColor(.secondary)
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Avenir Next Demi Bold", size: 12))
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color(red: 0.22, green: 0.41, blue: 0.86))
            .foregroundColor(.white)
            .cornerRadius(8)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Avenir Next", size: 12))
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.9))
            .foregroundColor(Color(red: 0.18, green: 0.2, blue: 0.25))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private var sectionTitleFont: Font {
    .custom("Avenir Next Demi Bold", size: 13)
}
