import SwiftUI
import AppKit

private enum FocusField {
    case url
}

struct MenuBarContentView: View {
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var playbackController: PlaybackController
    @ObservedObject var downloadManager: DownloadManager

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: FocusField?

    @StateObject private var networkMonitor = NetworkMonitor()

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
    @Namespace private var tabNamespace
    @State private var suggestedTrack: Track?
    private let tabContentMinHeight: CGFloat = 420

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

        var shortcutKey: KeyEquivalent {
            switch self {
            case .listen:
                return "1"
            case .add:
                return "2"
            case .utilities:
                return "3"
            }
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [UI.base, UI.baseDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(GridBackground().opacity(0.12))
            VStack(alignment: .leading, spacing: 14) {
                headerRow
                tabBar
                VStack(alignment: .leading, spacing: 14) {
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
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                    .foregroundColor(UI.ink.opacity(0.7))
                                HStack(spacing: 8) {
                                    if let failedTrack, shouldOfferDownloadAnyway(failedTrack) {
                                        Button("Download Anyway") {
                                            Task {
                                                await downloadOnly(failedTrack)
                                            }
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
                        trackListSection
                    case .add:
                        addNewSection
                    case .utilities:
                        utilitiesSection
                    }
                }
                .padding(.bottom, 4)
                .frame(minHeight: tabContentMinHeight, alignment: .topLeading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            if let deleteCandidate {
                DialogOverlay(onBackgroundTap: { self.deleteCandidate = nil }) {
                    DialogCard(title: "Delete track?", message: "This removes the track and any downloaded audio.") {
                        HStack(spacing: 8) {
                            Button("Cancel") {
                                self.deleteCandidate = nil
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            Button("Delete") {
                                libraryStore.removeTrack(deleteCandidate)
                                self.deleteCandidate = nil
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
            }

            if let renameCandidate {
                DialogOverlay(onBackgroundTap: { self.renameCandidate = nil }) {
                    DialogCard(title: "Rename track", message: "Update the track display name.") {
                        DialogTextField(placeholder: "Display name", text: $renameText)
                        HStack(spacing: 8) {
                            Button("Cancel") {
                                self.renameCandidate = nil
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            Button("Save") {
                                var updated = renameCandidate
                                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                updated.displayName = trimmed
                                libraryStore.updateTrack(updated)
                                self.renameCandidate = nil
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
            }
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
                let warningValue: String?
                if available, let version, client.isVersionOutdated(version) {
                    warningValue = "Bundled yt-dlp version \(version) is older than \(YtDlpClient.minimumSupportedVersion)."
                } else if available, version == nil {
                    warningValue = "Unable to read yt-dlp version. Downloads may fail."
                } else {
                    warningValue = nil
                }
                await MainActor.run {
                    ytdlpMissing = !available
                    ytdlpVersion = version
                    ytdlpWarning = warningValue
                    ffmpegMissing = !ffmpegAvailable
                }
            }
            DispatchQueue.main.async {
                focusedField = selectedTab == .add ? .url : nil
            }
            updateSuggestedTrack()
        }
        .onChange(of: libraryStore.library) { _ in
            updateSuggestedTrack()
        }
        .onExitCommand {
            dismiss()
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LongPlay")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(UI.ink)
            }
            Spacer()
            Text("v0.1")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(UI.surface)
                .cornerRadius(UI.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: UI.cornerRadius)
                        .stroke(UI.border, lineWidth: 1)
                )
        }
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                    focusedField = tab == .add ? .url : nil
                } label: {
                    let isSelected = tab == selectedTab
                    Hoverable { hovering in
                        ZStack {
                            if isSelected {
                                RoundedRectangle(cornerRadius: UI.cornerRadius)
                                    .fill(UI.accent)
                                    .matchedGeometryEffect(id: "tab-pill", in: tabNamespace)
                            } else if hovering {
                                RoundedRectangle(cornerRadius: UI.cornerRadius)
                                    .fill(UI.surfaceAlt)
                            }
                            HStack(spacing: 6) {
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(tab.rawValue)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(isSelected ? UI.ink : UI.ink.opacity(0.8))
                        }
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(tab.shortcutKey, modifiers: [.command])
            }
        }
        .padding(4)
        .background(UI.surface)
        .cornerRadius(UI.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: UI.cornerRadius)
                .stroke(UI.border, lineWidth: 1)
        )
        .frame(height: 36)
    }

    private var nowPlayingSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Now Playing")
                    .font(sectionTitleFont)
                Text(nowPlayingTitle)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    StatusPill(label: nowPlayingStatus, color: nowPlayingStatusColor)
                    Spacer()
                    Button(playbackController.state == .playing ? "Pause" : "Play") {
                        handlePrimaryPlay()
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
                .disabled(!canControlPlayback)
                if let activeId = downloadManager.activeTrackId,
                   activeId == playbackController.currentTrack?.id,
                   let progress = downloadManager.progress {
                    ProgressBar(value: progress)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusLine: String {
        if downloadManager.activeTrackId != nil {
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

    private var trackListSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tracks")
                    .font(sectionTitleFont)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !filteredLibrary.isEmpty {
                            Text("My Library")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(UI.ink.opacity(0.7))
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
                        if filteredLibrary.isEmpty {
                            EmptyStateView(
                                title: "No tracks yet",
                                message: "Add a YouTube URL to start listening offline."
                            )
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var addNewSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add New")
                    .font(sectionTitleFont)
                LabeledTextField(
                    icon: "link",
                    placeholder: "YouTube URL",
                    text: $newURL,
                    focusedField: $focusedField,
                    field: .url,
                    onSubmit: addNewTrack
                )
                LabeledTextField(
                    icon: "pencil",
                    placeholder: "Display name (optional)",
                    text: $newDisplayName,
                    focusedField: $focusedField,
                    field: nil,
                    onSubmit: addNewTrack
                )
                if let validationError {
                    Text(validationError)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(UI.danger)
                }
                Button("Add") {
                    addNewTrack()
                }
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityLabel("Add track")
                .accessibilityIdentifier("AddTrackButton")
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
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
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(UI.danger)
                }
                Button {
                    showClearDownloadsConfirm = true
                } label: {
                    Label("Clear Downloads", systemImage: "trash")
                }
                .accessibilityLabel("Clear all downloads")
                .buttonStyle(SecondaryButtonStyle())
                if showClearDownloadsConfirm {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Remove all cached audio files?")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(UI.ink.opacity(0.7))
                        HStack(spacing: 8) {
                            Button("Clear") {
                                libraryStore.clearDownloads()
                                showClearDownloadsConfirm = false
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            Button("Cancel") {
                                showClearDownloadsConfirm = false
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(8)
                    .background(UI.surface)
                    .cornerRadius(UI.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: UI.cornerRadius)
                            .stroke(UI.border, lineWidth: 1)
                    )
                }
                Text("Cache: \(formattedBytes(libraryStore.cacheSizeBytes)) • Manual cleanup")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(UI.ink.opacity(0.7))
                Button {
                    copyDiagnostics()
                } label: {
                    Label("Copy Diagnostics", systemImage: "doc.on.doc")
                }
                .accessibilityLabel("Copy diagnostics")
                .buttonStyle(SecondaryButtonStyle())
                Divider()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
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
            focusedField = nil
            if name.isEmpty {
                Task {
                    if let title = await fetchTitleForTrack(track.sourceURL) {
                        await MainActor.run {
                            libraryStore.updateDisplayNameIfDefault(
                                trackId: track.id,
                                defaultName: track.videoId,
                                newName: title
                            )
                        }
                    }
                }
            }
            streamAndDownload(track)
        }
    }

    private var filteredLibrary: [Track] {
        libraryStore.library.userLibrary
    }


    private var nowPlayingTrack: Track? {
        if let current = playbackController.currentTrack {
            return libraryStore.track(withId: current.id) ?? current
        }
        return suggestedTrack
    }

    private var nowPlayingTitle: String {
        nowPlayingTrack?.displayName ?? "Nothing yet"
    }

    private var canControlPlayback: Bool {
        if playbackController.currentTrack != nil {
            return true
        }
        return nowPlayingTrack?.downloadState == .downloaded
    }

    private var nowPlayingStatus: String {
        if playbackController.currentTrack == nil, let track = nowPlayingTrack, track.downloadState != .downloaded {
            return "Not downloaded"
        }
        return playbackController.stateLabel
    }

    private var nowPlayingStatusColor: Color {
        if playbackController.currentTrack == nil, let track = nowPlayingTrack, track.downloadState != .downloaded {
            return UI.warning
        }
        return playbackController.stateColor
    }

    private func updateSuggestedTrack() {
        let allTracks = libraryStore.library.userLibrary
        if let lastPlayed = allTracks
            .filter({ $0.lastPlayedAt != nil })
            .max(by: { ($0.lastPlayedAt ?? .distantPast) < ($1.lastPlayedAt ?? .distantPast) }) {
            suggestedTrack = lastPlayed
            return
        }
        suggestedTrack = allTracks.randomElement()
    }

    private func handlePrimaryPlay() {
        if playbackController.state == .playing {
            playbackController.pause()
            return
        }
        if playbackController.currentTrack != nil {
            playbackController.resume()
            return
        }
        guard let fallback = nowPlayingTrack else { return }
        if fallback.downloadState == .downloaded {
            play(fallback)
            return
        }
        streamAndDownload(fallback)
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
            globalErrorMessage = nil
            failedTrack = nil
            DiagnosticsLogger.shared.log(level: "info", message: "Starting download for \(track.videoId)")

            await downloadOnly(track)
        }
    }

    private func fetchTitleForTrack(_ url: URL) async -> String? {
        let client = YtDlpClient()
        do {
            let metadata = try await client.resolveMetadata(url: url)
            return metadata.title
        } catch {
            DiagnosticsLogger.shared.log(level: "warning", message: "Title fetch failed: \(error.localizedDescription)")
            let fallback = await client.fetchTitleFallback(url: url)
            if fallback == nil {
                DiagnosticsLogger.shared.log(level: "warning", message: "Title fallback failed for \(url.absoluteString)")
            }
            return fallback
        }
    }

    private func streamAndDownload(_ track: Track) {
        Task {
            guard networkMonitor.isOnline else {
                var failed = track
                failed.downloadState = .failed
                failed.lastError = "No internet connection."
                libraryStore.updateTrack(failed)
                globalErrorMessage = "No internet connection."
                failedTrack = failed
                DiagnosticsLogger.shared.log(level: "warning", message: "Streaming blocked: offline")
                return
            }
            if track.downloadState != .resolving {
                var updated = libraryStore.track(withId: track.id) ?? track
                updated.downloadState = .resolving
                updated.lastError = nil
                libraryStore.updateTrack(updated)
            }
            do {
                let streamURL = try await YtDlpClient().fetchStreamURL(url: track.sourceURL)
                await MainActor.run {
                    playbackController.streamAndPlay(
                        track: track,
                        streamURL: streamURL,
                        startAt: track.playbackPositionSeconds
                    )
                }
            } catch {
                DiagnosticsLogger.shared.log(level: "warning", message: "Streaming failed: \(error.localizedDescription)")
            }
            await downloadOnly(track)
        }
    }

    private func downloadOnly(_ track: Track) async {
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
            var updated = libraryStore.track(withId: track.id) ?? track
            updated.downloadState = .downloading
            updated.lastError = nil
            libraryStore.updateTrack(updated)
            let fileURL = try await downloadManager.startDownload(for: updated)
            var completed = libraryStore.track(withId: updated.id) ?? updated
            completed.downloadState = .downloaded
            completed.downloadProgress = 1.0
            completed.localFilePath = fileURL.path
            if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let fileSize = attributes[.size] as? NSNumber {
                completed.fileSizeBytes = fileSize.int64Value
            }
            libraryStore.updateTrack(completed)
            libraryStore.refreshCacheSize()
            if let localURL = completed.localFilePath {
                try? playbackController.swapToLocalIfStreaming(trackId: completed.id, fileURL: URL(fileURLWithPath: localURL))
            }
            NotificationManager.shared.notifyDownloadComplete(track: completed)
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
            return "Preparing download…"
        }
        if track.downloadState == .failed, let error = track.lastError {
            return error
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
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayName)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                if let resolvedTitle = track.resolvedTitle, resolvedTitle != track.displayName {
                    Text(resolvedTitle)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(UI.ink.opacity(0.65))
                }
                if let progress {
                    Text(progress)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(UI.ink.opacity(0.6))
                }
            }
            Spacer(minLength: 6)
            statusPillView
            HStack(spacing: 6) {
                if track.downloadState == .downloaded {
                    TrackActionButton(icon: "play.fill", label: "Play", action: onPlay)
                    if isUserTrack, let onDelete {
                        TrackActionButton(icon: "trash", label: "Delete", action: onDelete)
                    } else {
                        TrackActionButton(icon: "trash", label: "Remove Download", action: onRemoveDownload)
                    }
                } else if track.downloadState == .downloading {
                    TrackActionButton(icon: "xmark.circle", label: "Cancel", action: onCancel)
                } else if track.downloadState == .failed {
                    TrackActionButton(icon: "arrow.clockwise", label: "Retry", accent: true, action: onRetry)
                    TrackActionButton(icon: "doc.on.doc", label: "Logs", action: onDiagnostics)
                } else {
                    TrackActionButton(icon: "arrow.down.circle", label: "Download", accent: true, action: onDownload)
                        .disabled(downloadDisabled)
                }
            }
        }
        .padding(6)
        .background(isHovering ? UI.surfaceAlt : UI.surface)
        .cornerRadius(UI.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: UI.cornerRadius)
                .stroke(UI.border, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
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

    private var statusPillView: some View {
        StatusPill(label: statusPillLabel, color: statusPillColor)
            .frame(width: 92, alignment: .leading)
    }

    private var statusPillLabel: String {
        switch track.downloadState {
        case .notDownloaded:
            return "Online"
        case .downloaded:
            return "Offline"
        case .resolving:
            return "Preparing"
        case .downloading:
            return "Downloading"
        case .failed:
            return "Issue"
        }
    }

    private var statusPillColor: Color {
        switch track.downloadState {
        case .notDownloaded:
            return UI.border
        case .downloaded:
            return UI.success
        case .resolving:
            return UI.warning
        case .downloading:
            return UI.accent
        case .failed:
            return UI.danger
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
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(UI.surface)
            .overlay(
                RoundedRectangle(cornerRadius: UI.cornerRadius)
                    .stroke(UI.border, lineWidth: 1.2)
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
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(UI.warning)
                    .font(.system(size: 16, weight: .semibold))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                    Text(message)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(UI.ink.opacity(0.7))
                    Button(actionTitle, action: action)
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Hoverable { hovering in
            configuration.label
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(hovering ? UI.accentHover : UI.accent)
                .foregroundColor(UI.ink)
                .cornerRadius(UI.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: UI.cornerRadius)
                        .stroke(UI.border, lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(configuration.isPressed ? 0.9 : 1)
        }
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Hoverable { hovering in
            configuration.label
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(hovering ? UI.surfaceAlt : UI.surface)
                .foregroundColor(UI.ink)
                .cornerRadius(UI.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: UI.cornerRadius)
                        .stroke(UI.border, lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(configuration.isPressed ? 0.9 : 1)
        }
    }
}

private var sectionTitleFont: Font {
    .system(size: 13, weight: .bold, design: .monospaced)
}

private enum UI {
    static let base = Color(red: 0.96, green: 0.96, blue: 0.95)
    static let baseDeep = Color(red: 0.91, green: 0.91, blue: 0.9)
    static let surface = Color.white
    static let surfaceAlt = Color(red: 0.93, green: 0.93, blue: 0.92)
    static let ink = Color(red: 0.1, green: 0.1, blue: 0.1)
    static let border = Color.black.opacity(0.8)
    static let accent = Color(red: 0.15, green: 0.95, blue: 0.6)
    static let accentHover = Color(red: 0.1, green: 0.9, blue: 0.55)
    static let success = Color(red: 0.12, green: 0.8, blue: 0.45)
    static let warning = Color(red: 1.0, green: 0.76, blue: 0.2)
    static let danger = Color(red: 0.95, green: 0.25, blue: 0.35)
    static let cornerRadius: CGFloat = 6
}

private struct StatusPill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(UI.surface)
            .foregroundColor(UI.ink)
            .cornerRadius(UI.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: UI.cornerRadius)
                    .stroke(color, lineWidth: 1)
            )
    }
}

private struct ArtworkBadge: View {
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: UI.cornerRadius)
                .fill(UI.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: UI.cornerRadius)
                        .stroke(UI.border, lineWidth: 1)
                )
            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(UI.ink)
        }
        .frame(width: 26, height: 26)
    }
}

private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(UI.surface)
                    .overlay(
                        Capsule()
                            .stroke(UI.border, lineWidth: 1)
                    )
                Capsule()
                    .fill(UI.accent)
                    .frame(width: max(6, proxy.size.width * CGFloat(value)))
            }
        }
        .frame(height: 6)
    }
}

private struct LabeledTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var focusedField: FocusState<FocusField?>.Binding
    let field: FocusField?
    let onSubmit: () -> Void
    @State private var isHovering = false

    var body: some View {
        let isFocused = focusedField.wrappedValue == field
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(UI.ink.opacity(0.7))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
                .focused(focusedField, equals: field)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isHovering ? UI.surfaceAlt : UI.surface)
        .cornerRadius(UI.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: UI.cornerRadius)
                .stroke(isFocused ? UI.accent : UI.border, lineWidth: isFocused ? 2 : 1)
        )
        .accessibilityLabel(placeholder)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct IconButton: View {
    let icon: String
    let label: String
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Group {
            if prominent {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                        Text(label)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                        Text(label)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct TrackActionButton: View {
    let icon: String
    let label: String
    var accent: Bool = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
                .foregroundColor(UI.ink)
                .opacity(isHovering ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct DialogOverlay<Content: View>: View {
    let onBackgroundTap: (() -> Void)?
    let content: Content

    init(onBackgroundTap: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.onBackgroundTap = onBackgroundTap
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    onBackgroundTap?()
                }
            content
        }
    }
}

private struct DialogCard<Actions: View>: View {
    let title: String
    let message: String
    let actions: Actions

    init(title: String, message: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(UI.ink)
            Text(message)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(UI.ink.opacity(0.7))
            actions
        }
        .padding(14)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: UI.cornerRadius)
                .fill(UI.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: UI.cornerRadius)
                .stroke(UI.border, lineWidth: 1)
        )
    }
}

private struct DialogTextField: View {
    let placeholder: String
    @Binding var text: String
    @State private var isHovering = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(isHovering ? UI.surfaceAlt : UI.surface)
            .cornerRadius(UI.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: UI.cornerRadius)
                    .stroke(UI.border, lineWidth: 1)
            )
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

private struct EmptyStateView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
            Text(message)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(UI.ink.opacity(0.7))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UI.surface)
        .cornerRadius(UI.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: UI.cornerRadius)
                .stroke(UI.border, lineWidth: 1)
        )
    }
}

private struct Hoverable<Content: View>: View {
    let content: (Bool) -> Content
    @State private var isHovering = false

    var body: some View {
        content(isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

private struct GridBackground: View {
    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                var path = Path()
                let spacing: CGFloat = 24
                let verticalCount = Int(size.width / spacing)
                let horizontalCount = Int(size.height / spacing)
                for index in 0...verticalCount {
                    let x = CGFloat(index) * spacing
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for index in 0...horizontalCount {
                    let y = CGFloat(index) * spacing
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(UI.border.opacity(0.18)), lineWidth: 1)
            }
        }
    }
}

private extension PlaybackState {
    var label: String {
        switch self {
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

    var color: Color {
        switch self {
        case .idle:
            return UI.ink.opacity(0.6)
        case .playing:
            return UI.success
        case .paused:
            return UI.warning
        case .error:
            return UI.danger
        }
    }
}

private extension PlaybackController {
    var stateLabel: String { state.label }
    var stateColor: Color { state.color }
}

private extension Track {
    var stateColor: Color {
        switch downloadState {
        case .downloaded:
            return UI.success
        case .downloading, .resolving:
            return UI.accent
        case .failed:
            return UI.danger
        case .notDownloaded:
            return UI.ink.opacity(0.6)
        }
    }
}
