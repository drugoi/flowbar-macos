import SwiftUI
import AppKit
import ServiceManagement

private enum FocusField {
    case url
}

private struct BatchAddError: Identifiable {
    let id = UUID()
    let input: String
    let message: String
}

struct MenuBarContentView: View {
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var playbackController: PlaybackController
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var updateManager: UpdateManager

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: FocusField?

    @StateObject private var networkMonitor = NetworkMonitor()

    @State private var newURL = ""
    @State private var newDisplayName = ""
    @State private var validationError: String?
    @State private var batchAddErrors: [BatchAddError] = []
    @State private var suppressBatchErrorClear = false
    @State private var ytdlpMissing = false
    @State private var showClearDownloadsConfirm = false
    @State private var deleteCandidate: Track?
    @State private var globalErrorMessage: String?
    @State private var failedTrack: Track?
    @State private var renameCandidate: Track?
    @State private var renameText: String = ""
    @State private var didLogAppearance = false
    @State private var ytdlpVersion: String?
    @State private var ytdlpWarning: String?
    @State private var ffmpegMissing = false
    @State private var selectedTab: Tab = .listen
    @Namespace private var tabNamespace
    @State private var suggestedTrack: Track?
    @State private var startAtLoginEnabled = false
    @State private var startAtLoginBusy = false
    @State private var startAtLoginError: String?
    @State private var isScrubbing = false
    @State private var scrubberOverrideTime: TimeInterval?
    private let tabContentMinHeight: CGFloat = 420
    private let skipInterval: TimeInterval = 15
    private let sleepTimerOptions: [(label: String, duration: TimeInterval)] = [
        ("15 min", 15 * 60),
        ("30 min", 30 * 60),
        ("60 min", 60 * 60)
    ]
    private static let sleepTimerHourMinuteFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
    private static let sleepTimerMinuteSecondFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
    private let bytesPerGB: Int64 = 1_073_741_824

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
                colors: [UI.base, UI.baseAlt],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(UI.inkMuted)
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
                                logUserAction("Delete track cancelled")
                                self.deleteCandidate = nil
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            Button("Delete") {
                                logUserAction("Delete track confirmed: \(deleteCandidate.videoId)")
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
                                logUserAction("Rename track cancelled")
                                self.renameCandidate = nil
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            Button("Save") {
                                var updated = renameCandidate
                                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                updated.displayName = trimmed
                                libraryStore.updateTrack(updated)
                                logUserAction("Rename track saved: \(renameCandidate.videoId)")
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
            if !didLogAppearance {
                logUserAction("Menu opened")
                didLogAppearance = true
            }
            playbackController.positionUpdateHandler = { [weak libraryStore, weak playbackController] time in
                guard let trackId = playbackController?.currentTrack?.id else { return }
                DispatchQueue.main.async {
                    libraryStore?.updatePlaybackPosition(trackId: trackId, position: time)
                }
            }
            playbackController.streamingFailedHandler = { track in
                DispatchQueue.main.async {
                    globalErrorMessage = "Streaming failed. We'll keep downloading and play offline once ready."
                    failedTrack = track
                }
            }
            playbackController.playbackEndedHandler = { [weak playbackController] finished in
                DispatchQueue.main.async {
                    guard playbackController != nil else { return }
                    handlePlaybackEnded(finished)
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
            refreshStartAtLoginState()
        }
        .onChange(of: libraryStore.library) { _ in
            updateSuggestedTrack()
        }
        .onChange(of: playbackController.currentTrack?.id) { _ in
            scrubberOverrideTime = nil
            isScrubbing = false
        }
        .onExitCommand {
            dismiss()
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LongPlay")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(UI.ink)
            }
            Spacer()
            Text("v0.1")
                .font(.system(size: 11, weight: .semibold))
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(UI.surfaceAlt)
                .cornerRadius(UI.smallRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: UI.smallRadius)
                        .stroke(UI.border, lineWidth: 1)
                )
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                    focusedField = tab == .add ? .url : nil
                    logUserAction("Switched tab: \(tab.rawValue)")
                } label: {
                    let isSelected = tab == selectedTab
                    Hoverable { hovering in
                        ZStack {
                            if isSelected {
                                RoundedRectangle(cornerRadius: UI.smallRadius)
                                    .fill(UI.accent.opacity(0.12))
                                    .matchedGeometryEffect(id: "tab-pill", in: tabNamespace)
                            } else if hovering {
                                RoundedRectangle(cornerRadius: UI.smallRadius)
                                    .fill(UI.surfaceHover)
                            }
                            HStack(spacing: 4) {
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(tab.rawValue)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(isSelected ? UI.accent : UI.ink)
                        }
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(tab.shortcutKey, modifiers: [.command])
            }
        }
        .padding(3)
        .background(UI.surface)
        .cornerRadius(UI.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: UI.cornerRadius)
                .stroke(UI.border, lineWidth: 1)
        )
        .frame(height: 32)
    }

    private var nowPlayingSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Now Playing")
                    .font(sectionTitleFont)
                Text(nowPlayingTitle)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    StatusPill(label: nowPlayingStatus, color: nowPlayingStatusColor)
                    Spacer()
                    Button {
                        logUserAction("Skip back tapped")
                        playbackController.skip(by: -skipInterval)
                    } label: {
                        Label("Back", systemImage: "gobackward")
                            .labelStyle(.iconOnly)
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .accessibilityLabel("Skip back \(Int(skipInterval)) seconds")
                    .disabled(!canSkip)
                    .buttonStyle(SecondaryButtonStyle())
                    Button(playbackController.state == .playing ? "Pause" : "Play") {
                        logUserAction("Primary play/pause tapped")
                        handlePrimaryPlay()
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    .accessibilityLabel(playbackController.state == .playing ? "Pause playback" : "Resume playback")
                    .buttonStyle(PrimaryButtonStyle())
                    Button("Stop") {
                        logUserAction("Stop playback tapped")
                        playbackController.stop()
                        playbackController.cancelSleepTimer()
                        if let trackId = playbackController.currentTrack?.id {
                            libraryStore.resetPlaybackPosition(trackId: trackId)
                        }
                    }
                    .accessibilityLabel("Stop playback")
                    .buttonStyle(SecondaryButtonStyle())
                    Button {
                        logUserAction("Skip forward tapped")
                        playbackController.skip(by: skipInterval)
                    } label: {
                        Label("Forward", systemImage: "goforward")
                            .labelStyle(.iconOnly)
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .accessibilityLabel("Skip forward \(Int(skipInterval)) seconds")
                    .disabled(!canSkip)
                    .buttonStyle(SecondaryButtonStyle())
                }
                .disabled(!canControlPlayback)
                VStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { scrubberDisplayTime },
                            set: { newValue in
                                let upperBound = max(scrubberDuration, 0)
                                let clampedValue = min(max(newValue, 0), upperBound)
                                scrubberOverrideTime = clampedValue
                            }
                        ),
                        in: 0...max(scrubberDuration, 0),
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if !editing, let finalValue = scrubberOverrideTime {
                                if scrubberDuration > 0 {
                                    playbackController.seek(to: finalValue)
                                }
                                scrubberOverrideTime = nil
                            }
                        }
                    )
                    .disabled(!canScrub)
                    .accessibilityLabel("Playback position")
                    .accessibilityValue({
                        let current = formattedTime(scrubberDisplayTime)
                        let total = formattedTime(scrubberDuration)
                        if current == "--:--" && total == "--:--" {
                            return "Position unavailable"
                        }
                        return "\(current) of \(total)"
                    }())
                    HStack {
                        Text(formattedTime(scrubberDisplayTime))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(UI.inkMuted)
                        Spacer()
                        Text(formattedDuration(scrubberDuration))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(UI.inkMuted)
                    }
                }
                HStack(spacing: 12) {
                    Text("Speed")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(UI.ink)
                    Spacer()
                    Picker("Speed", selection: $playbackController.playbackSpeed) {
                        ForEach(PlaybackController.availableSpeeds, id: \.self) { speed in
                            Text(speedLabel(speed))
                                .tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 220)
                }
                HStack(alignment: .center, spacing: 8) {
                    Text("Sleep Timer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(UI.inkMuted)
                    Spacer()
                    Menu {
                        Button("Cancel Timer", action: playbackController.cancelSleepTimer)
                            .disabled(!playbackController.sleepTimerIsActive)
                        Divider()
                        ForEach(sleepTimerOptions, id: \.duration) { option in
                            Button(option.label) {
                                playbackController.startSleepTimer(duration: option.duration)
                            }
                        }
                    } label: {
                        Text(sleepTimerMenuLabel)
                    }
                    .disabled(!canControlPlayback)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel("Sleep timer selection")
                }
                .disabled(!canControlPlayback)
                Text(sleepTimerStatus)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(UI.inkMuted)
                    .accessibilityLabel("Sleep timer status")
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
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(UI.inkMuted)
                            ForEach(filteredLibrary) { track in
                                TrackRow(
                                    track: track,
                                    progress: progressText(for: track),
                                    downloadDisabled: downloadManager.activeTrackId != nil && downloadManager.activeTrackId != track.id,
                                    isUserTrack: true,
                                    onPlay: {
                                        logUserAction("Play track tapped: \(track.videoId)")
                                        play(track)
                                    },
                                    onDownload: {
                                        logUserAction("Download track tapped: \(track.videoId)")
                                        resolveAndDownload(track)
                                    },
                                    onRetry: {
                                        logUserAction("Retry download tapped: \(track.videoId)")
                                        resolveAndDownload(track)
                                    },
                                    onCancel: {
                                        logUserAction("Cancel download tapped: \(track.videoId)")
                                        cancelDownload(for: track)
                                    },
                                    onRemoveDownload: {
                                        logUserAction("Remove download tapped: \(track.videoId)")
                                        libraryStore.removeDownload(for: track)
                                    },
                                    onDiagnostics: {
                                        logUserAction("Track diagnostics tapped: \(track.videoId)")
                                        copyDiagnostics()
                                    },
                                    onDelete: {
                                        logUserAction("Delete track tapped: \(track.videoId)")
                                        deleteCandidate = track
                                    },
                                    onRename: {
                                        logUserAction("Rename track tapped: \(track.videoId)")
                                        beginRename(track)
                                    }
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
                .accessibilityElement(children: .contain)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("LongPlayMainWindow")
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
                .onChange(of: newURL) { _ in
                    if suppressBatchErrorClear {
                        suppressBatchErrorClear = false
                        return
                    }
                    if validationError != nil {
                        validationError = nil
                    }
                    if !batchAddErrors.isEmpty {
                        batchAddErrors = []
                    }
                }
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
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(UI.danger)
                }
                if !batchAddErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Some URLs need attention:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(UI.danger)
                        ForEach(batchAddErrors) { error in
                            Text("• \(error.input) — \(error.message)")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(UI.danger)
                        }
                    }
                }
                Button("Add") {
                    logUserAction("Add track tapped")
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
                SettingsCard(title: "Updates") {
                    settingsActionRow(
                        title: "Check for Updates",
                        subtitle: "Check the update feed now.",
                        actionTitle: "Check"
                    ) {
                        logUserAction("Check for updates tapped")
                        updateManager.checkForUpdates()
                    }

                    settingsToggle(
                        title: "Check Automatically",
                        subtitle: "Look for updates in the background.",
                        isOn: updateAutoCheckBinding
                    )
                    if let errorMessage = updateManager.errorMessage {
                        settingsErrorText(errorMessage)
                    } else if let lastCheckedAt = updateManager.lastCheckedAt {
                        Text("Last checked: \(relativeDateString(lastCheckedAt))")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(UI.inkMuted)
                    }
                }

                SettingsCard(title: "System") {
                    settingsToggle(
                        title: "Start at Login",
                        subtitle: "Launch LongPlay when you sign in.",
                        isOn: startAtLoginBinding
                    )
                    .disabled(startAtLoginBusy)
                    if let startAtLoginError {
                        settingsErrorText(startAtLoginError)
                    }

                    settingsActionRow(
                        title: "Copy Diagnostics",
                        subtitle: "Copy logs to your clipboard.",
                        actionTitle: "Copy"
                    ) {
                        logUserAction("Copy diagnostics tapped")
                        copyDiagnostics()
                    }
                    if let lastError = libraryStore.lastError {
                        settingsErrorText(lastError)
                    }
                }

                SettingsCard(title: "Storage") {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cache limit")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(UI.ink)
                            Text("Auto-evict least-recently-played downloads.")
                                .font(.system(size: 10.5, weight: .regular))
                                .foregroundColor(UI.inkMuted)
                        }
                        Spacer()
                        Stepper(value: cacheLimitGBBinding, in: 1...50, step: 1) {
                            Text("\(cacheLimitGBBinding.wrappedValue) GB")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(UI.ink)
                        }
                        .controlSize(.small)
                    }
                    Button {
                        logUserAction("Clear downloads tapped")
                        showClearDownloadsConfirm = true
                    } label: {
                        settingsButtonLabel(title: "Clear Downloads", systemImage: "trash")
                    }
                    .accessibilityLabel("Clear all downloads")
                    .buttonStyle(SecondaryButtonStyle())
                    .confirmationDialog(
                        "Remove all cached audio files?",
                        isPresented: $showClearDownloadsConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Clear Downloads", role: .destructive) {
                            logUserAction("Clear downloads confirmed")
                            libraryStore.clearDownloads()
                        }
                        Button("Cancel", role: .cancel) {
                            logUserAction("Clear downloads cancelled")
                        }
                    }
                    Text("Cache: \(formattedBytes(libraryStore.cacheSizeBytes)) of \(formattedBytes(libraryStore.cacheLimitBytes))")
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundColor(UI.inkMuted)
                }
                Divider()
                Button {
                    logUserAction("Quit tapped")
                    NSApplication.shared.terminate(nil)
                } label: {
                    settingsButtonLabel(title: "Quit", systemImage: "power")
                }
                .accessibilityLabel("Quit LongPlay")
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var updateAutoCheckBinding: Binding<Bool> {
        Binding(
            get: { updateManager.automaticallyChecksForUpdates },
            set: { updateManager.automaticallyChecksForUpdates = $0 }
        )
    }

    private var updateAutoDownloadBinding: Binding<Bool> {
        Binding(
            get: { updateManager.automaticallyDownloadsUpdates },
            set: { updateManager.automaticallyDownloadsUpdates = $0 }
        )
    }

    private var cacheLimitGBBinding: Binding<Int> {
        Binding(
            get: {
                let value = Double(libraryStore.cacheLimitBytes) / Double(bytesPerGB)
                return max(1, Int(value.rounded()))
            },
            set: { newValue in
                let maxGB = Double(Int64.max) / Double(bytesPerGB)
                let clampedGB = min(max(1, Double(newValue)), maxGB)
                let bytesDouble = clampedGB * Double(bytesPerGB)
                let safeBytesDouble = min(max(0, bytesDouble), Double(Int64.max))
                let bytes = Int64(safeBytesDouble)
                libraryStore.updateCacheLimit(
                    bytes: bytes,
                    excludingTrackId: playbackController.currentTrack?.id
                )
            }
        )
    }

    private var updateNotifyBinding: Binding<Bool> {
        Binding(
            get: { updateManager.notifyWhenUpdateAvailable },
            set: { updateManager.notifyWhenUpdateAvailable = $0 }
        )
    }

    private func addNewTrack() {
        logUserAction("Add track submitted")
        validationError = nil
        batchAddErrors = []
        globalErrorMessage = nil
        failedTrack = nil
        let entries = BatchURLParser.parse(newURL)
        guard !entries.isEmpty else {
            validationError = "Enter at least one YouTube URL."
            return
        }
        let name = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let useCustomName = entries.count == 1 && !name.isEmpty
        var addedTracks: [Track] = []

        for entry in entries {
            switch URLValidator.validate(entry) {
            case .failure(let error):
                batchAddErrors.append(BatchAddError(input: entry, message: error.localizedDescription))
                DiagnosticsLogger.shared.log(level: "warning", message: "URL validation failed: \(entry) - \(error.localizedDescription)")
            case .success(let validated):
                let displayName = useCustomName ? name : validated.videoId
                var track = Track.makeNew(
                    sourceURL: validated.canonicalURL,
                    videoId: validated.videoId,
                    displayName: displayName
                )
                track.downloadState = .resolving
                libraryStore.addToLibrary(track)
                DiagnosticsLogger.shared.log(level: "info", message: "Added track \(validated.videoId)")
                addedTracks.append(track)
            }
        }

        guard !addedTracks.isEmpty else { return }
        if batchAddErrors.isEmpty {
            suppressBatchErrorClear = true
            newURL = ""
            newDisplayName = ""
            selectedTab = .listen
            focusedField = nil
        } else {
            suppressBatchErrorClear = true
            newURL = batchAddErrors.map(\.input).joined(separator: "\n")
            newDisplayName = ""
            selectedTab = .add
            focusedField = .url
        }
        if entries.count == 1, let track = addedTracks.first {
            if !useCustomName {
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
        } else {
            fetchTitlesForBatch(addedTracks)
            startBatchDownloads(addedTracks)
        }
    }

    private func startBatchDownloads(_ tracks: [Track]) {
        Task {
            for track in tracks {
                await waitForDownloadSlot()
                await downloadOnly(track)
            }
        }
    }

    private func waitForDownloadSlot() async {
        while downloadManager.activeTrackId != nil {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func fetchTitlesForBatch(_ tracks: [Track]) {
        Task {
            for track in tracks {
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

    private var scrubberDuration: TimeInterval {
        if playbackController.duration > 0 {
            return playbackController.duration
        }
        if let duration = nowPlayingTrack?.durationSeconds, duration > 0 {
            return duration
        }
        return 0
    }

    private var scrubberCurrentTime: TimeInterval {
        if playbackController.currentTrack != nil {
            if scrubberDuration > 0 {
                return min(playbackController.currentTime, scrubberDuration)
            }
            return playbackController.currentTime
        }
        return 0
    }

    private var scrubberDisplayTime: TimeInterval {
        scrubberOverrideTime ?? scrubberCurrentTime
    }

    private var canScrub: Bool {
        canControlPlayback && playbackController.currentTrack != nil && scrubberDuration > 0
    }

    private var canSkip: Bool {
        playbackController.currentTrack != nil
    }

    private var sleepTimerMenuLabel: String {
        guard let remaining = playbackController.sleepTimerRemaining else {
            return "Off"
        }
        return formattedSleepTimer(remaining)
    }

    private var sleepTimerStatus: String {
        guard let remaining = playbackController.sleepTimerRemaining else {
            return "Sleep timer: Off"
        }
        return "Sleep timer: \(formattedSleepTimer(remaining)) remaining"
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

    private var startAtLoginBinding: Binding<Bool> {
        Binding(
            get: { startAtLoginEnabled },
            set: { newValue in
                startAtLoginEnabled = newValue
                setStartAtLogin(newValue)
            }
        )
    }

    private func refreshStartAtLoginState() {
        guard #available(macOS 13.0, *) else {
            startAtLoginEnabled = false
            return
        }
        startAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func setStartAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        logUserAction("Start at Login toggled: \(enabled ? "on" : "off")")
        startAtLoginBusy = true
        startAtLoginError = nil
        Task {
            do {
                if enabled {
                    try await SMAppService.mainApp.register()
                } else {
                    try await SMAppService.mainApp.unregister()
                }
            } catch {
                await MainActor.run {
                    startAtLoginError = error.localizedDescription
                }
            }
            await MainActor.run {
                startAtLoginBusy = false
                refreshStartAtLoginState()
            }
        }
    }

    private func handlePrimaryPlay() {
        logUserAction("Primary playback toggled")
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
        logUserAction("Resolve download for \(track.videoId)")
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
        logUserAction("Stream then download for \(track.videoId)")
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
        logUserAction("Download started for \(track.videoId)")
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
            let excludingId = playbackController.currentTrack?.id
            DispatchQueue.global(qos: .background).async {
                libraryStore.enforceCacheLimit(excludingTrackId: excludingId)
            }
            if let localURL = completed.localFilePath {
                try? playbackController.swapToLocalIfStreaming(trackId: completed.id, fileURL: URL(fileURLWithPath: localURL))
            }
            if playbackController.currentTrack?.id == completed.id,
               playbackController.state == .error {
                play(completed)
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
        logUserAction("Play track \(track.videoId)")
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

    private func handlePlaybackEnded(_ finished: Track?) {
        logUserAction("Playback ended")
        let tracks = libraryStore.library.userLibrary
        guard !tracks.isEmpty else { return }
        let nextTrack: Track
        if let finished, let index = tracks.firstIndex(where: { $0.id == finished.id }) {
            let nextIndex = (index + 1) % tracks.count
            nextTrack = tracks[nextIndex]
        } else {
            nextTrack = tracks[0]
        }
        if nextTrack.downloadState == .downloaded {
            play(nextTrack)
        } else {
            streamAndDownload(nextTrack)
        }
    }

    private func cancelDownload(for track: Track) {
        logUserAction("Download cancelled for \(track.videoId)")
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
        logUserAction("Begin rename for \(track.videoId)")
        renameCandidate = track
        renameText = track.displayName
    }

    private func shouldOfferDownloadAnyway(_ track: Track) -> Bool {
        guard let error = track.lastError?.lowercased() else { return false }
        return error.contains("timed out")
    }

    private func copyDiagnostics() {
        DiagnosticsLogger.shared.log(level: "info", message: "Diagnostics copied to clipboard")
        let diagnostics = DiagnosticsLogger.shared.formattedDiagnostics()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
    }

    private func logUserAction(_ message: String) {
        DiagnosticsLogger.shared.log(level: "info", message: "UI: \(message)")
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "--:--" }
        return formattedTime(seconds)
    }
    private func formattedSleepTimer(_ remaining: TimeInterval) -> String {
        let clampedRemaining = max(0, remaining)
        let formatter = clampedRemaining >= 3600
            ? Self.sleepTimerHourMinuteFormatter
            : Self.sleepTimerMinuteSecondFormatter
        return formatter.string(from: clampedRemaining) ?? "0:00"
    }

    private func relativeDateString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func speedLabel(_ speed: Double) -> String {
        if speed == 1.0 {
            return "1.0x"
        }
        var formatted = String(format: "%.2f", speed)
        while formatted.contains(".") && (formatted.hasSuffix("0") || formatted.hasSuffix(".")) {
            formatted.removeLast()
        }
        return "\(formatted)x"
    }

    private func settingsToggle(title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(UI.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundColor(UI.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.vertical, 1)
    }

    private func settingsActionRow(
        title: String,
        subtitle: String? = nil,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(UI.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundColor(UI.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.vertical, 1)
    }

    private func settingsButtonLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
    }

    private func settingsErrorText(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11, weight: .regular))
            .foregroundColor(UI.danger)
            .fixedSize(horizontal: false, vertical: true)
    }

    private struct SettingsCard<Content: View>: View {
        let title: String
        let content: Content

        init(title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(sectionTitleFont)
                    .foregroundColor(UI.ink)
                content
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(UI.surfaceAlt)
            .cornerRadius(UI.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: UI.cornerRadius)
                    .stroke(UI.border, lineWidth: 1)
            )
        }
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
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityIdentifier("TrackTitle_\(track.videoId)")
                if let resolvedTitle = track.resolvedTitle, resolvedTitle != track.displayName {
                    Text(resolvedTitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(UI.inkMuted)
                }
                if let progress {
                    Text(progress)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(UI.inkMuted)
                }
            }
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                statusPillView
                actionsView
                    .frame(width: 56, alignment: .trailing)
            }
            .frame(width: 148, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(isHovering ? UI.surfaceHover : UI.surface)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("TrackRow_\(track.videoId)")
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
            .frame(width: 84, alignment: .leading)
    }

    private var actionsView: some View {
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(UI.surface)
            .cornerRadius(UI.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: UI.cornerRadius)
                    .stroke(UI.border, lineWidth: 1)
            )
            .shadow(color: UI.shadow, radius: 8, x: 0, y: 3)
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
                        .font(.system(size: 13, weight: .semibold))
                    Text(message)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(UI.inkMuted)
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
                .font(.system(size: 12, weight: .semibold))
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .background(hovering ? UI.accentHover : UI.accent)
                .foregroundColor(.white)
                .cornerRadius(UI.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: UI.cornerRadius)
                        .stroke(Color.clear, lineWidth: 0)
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
                .font(.system(size: 12, weight: .medium))
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .background(hovering ? UI.surfaceHover : UI.surface)
                .foregroundColor(UI.ink)
                .cornerRadius(UI.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: UI.cornerRadius)
                        .stroke(hovering ? UI.borderHover : UI.border, lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(configuration.isPressed ? 0.9 : 1)
        }
    }
}

private var sectionTitleFont: Font {
    .system(size: 12, weight: .semibold)
}

private enum UI {
    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static let base = dynamicColor(
        light: NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.95, alpha: 1),
        dark: NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.11, alpha: 1)
    )
    static let baseAlt = dynamicColor(
        light: NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.93, alpha: 1),
        dark: NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)
    )
    static let surface = dynamicColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 1),
        dark: NSColor(calibratedWhite: 0.17, alpha: 1)
    )
    static let surfaceAlt = dynamicColor(
        light: NSColor(calibratedWhite: 0.96, alpha: 1),
        dark: NSColor(calibratedWhite: 0.22, alpha: 1)
    )
    static let surfaceHover = dynamicColor(
        light: NSColor(calibratedWhite: 0.94, alpha: 1),
        dark: NSColor(calibratedWhite: 0.26, alpha: 1)
    )
    static let ink = dynamicColor(
        light: NSColor(calibratedWhite: 0.12, alpha: 1),
        dark: NSColor(calibratedWhite: 0.92, alpha: 1)
    )
    static let inkMuted = dynamicColor(
        light: NSColor(calibratedWhite: 0.42, alpha: 1),
        dark: NSColor(calibratedWhite: 0.70, alpha: 1)
    )
    static let border = dynamicColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.06),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.14)
    )
    static let borderHover = dynamicColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.10),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.20)
    )
    static let accent = dynamicColor(
        light: NSColor(calibratedRed: 0.28, green: 0.55, blue: 0.9, alpha: 1),
        dark: NSColor(calibratedRed: 0.35, green: 0.65, blue: 0.98, alpha: 1)
    )
    static let accentHover = dynamicColor(
        light: NSColor(calibratedRed: 0.24, green: 0.50, blue: 0.85, alpha: 1),
        dark: NSColor(calibratedRed: 0.30, green: 0.60, blue: 0.95, alpha: 1)
    )
    static let success = dynamicColor(
        light: NSColor(calibratedRed: 0.22, green: 0.70, blue: 0.42, alpha: 1),
        dark: NSColor(calibratedRed: 0.28, green: 0.80, blue: 0.50, alpha: 1)
    )
    static let warning = dynamicColor(
        light: NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.20, alpha: 1),
        dark: NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.30, alpha: 1)
    )
    static let danger = dynamicColor(
        light: NSColor(calibratedRed: 0.92, green: 0.26, blue: 0.38, alpha: 1),
        dark: NSColor(calibratedRed: 0.98, green: 0.35, blue: 0.45, alpha: 1)
    )
    static let shadow = dynamicColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.06),
        dark: NSColor(calibratedWhite: 0.0, alpha: 0.35)
    )
    static let overlayScrim = dynamicColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.18),
        dark: NSColor(calibratedWhite: 0.0, alpha: 0.55)
    )
    static let cornerRadius: CGFloat = 10
    static let smallRadius: CGFloat = 8
}

private struct StatusPill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(UI.surfaceAlt)
            .foregroundColor(UI.ink)
            .cornerRadius(UI.smallRadius)
            .overlay(
                RoundedRectangle(cornerRadius: UI.smallRadius)
                    .stroke(color.opacity(0.7), lineWidth: 1)
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
                    .fill(UI.surfaceAlt)
                    .overlay(
                        Capsule()
                            .stroke(UI.border, lineWidth: 1)
                    )
                Capsule()
                    .fill(UI.accent)
                    .frame(width: max(6, proxy.size.width * CGFloat(value)))
            }
        }
        .frame(height: 7)
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
                .foregroundColor(UI.inkMuted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
                .focused(focusedField, equals: field)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isHovering ? UI.surfaceHover : UI.surface)
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
                .frame(width: 24, height: 24)
                .foregroundColor(UI.ink)
                .background(isHovering ? UI.surfaceHover : Color.clear)
                .cornerRadius(UI.smallRadius)
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
            UI.overlayScrim
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(UI.ink)
            Text(message)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(UI.inkMuted)
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
        .shadow(color: UI.shadow, radius: 10, x: 0, y: 4)
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
            .background(isHovering ? UI.surfaceHover : UI.surface)
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
                .font(.system(size: 12, weight: .semibold))
            Text(message)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(UI.inkMuted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UI.surfaceAlt)
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
            return UI.inkMuted
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
            return UI.inkMuted
        }
    }
}
