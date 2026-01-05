import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var playbackController: PlaybackController
    @ObservedObject var downloadManager: DownloadManager

    @State private var searchText = ""
    @State private var newURL = ""
    @State private var newDisplayName = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                Button("Stop") {
                    playbackController.stop()
                }
            }
            .disabled(playbackController.currentTrack == nil)
            Text(statusLine)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var statusLine: String {
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
                            TrackRow(track: track)
                        }
                    }
                    if !filteredLibrary.isEmpty {
                        Text("My Library")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        ForEach(filteredLibrary) { track in
                            TrackRow(track: track)
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
            TextField("Display name (optional)", text: $newDisplayName)
                .textFieldStyle(.roundedBorder)
            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Button("Add") {
                addNewTrack()
            }
        }
    }

    private var utilitiesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Utilities")
                .font(.headline)
            Button("Clear Downloads") {
                // TODO: Implement cache clearing.
            }
            Button("Copy Diagnostics") {
                let diagnostics = DiagnosticsLogger.shared.formattedDiagnostics()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(diagnostics, forType: .string)
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func addNewTrack() {
        validationError = nil
        switch URLValidator.validate(newURL) {
        case .failure(let error):
            validationError = error.localizedDescription
        case .success(let validated):
            let name = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? validated.videoId : name
            let track = Track.makeNew(
                sourceURL: validated.canonicalURL,
                videoId: validated.videoId,
                displayName: displayName
            )
            libraryStore.addToLibrary(track)
            newURL = ""
            newDisplayName = ""
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
}

private struct TrackRow: View {
    let track: Track

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
            }
            Spacer()
            Button("Play") {
                // TODO: Hook up playback when downloads are ready.
            }
            .buttonStyle(.bordered)
        }
        .padding(6)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }
}
