import Foundation
import AVFoundation
import Combine

enum PlaybackState: String {
    case idle
    case playing
    case paused
    case error
}

final class PlaybackController: ObservableObject {
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var currentTrack: Track?

    private var player: AVAudioPlayer?
    private var positionTimer: Timer?

    func loadAndPlay(track: Track, fileURL: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.prepareToPlay()
            self.player = player
            currentTrack = track
            state = .playing
            player.play()
        } catch {
            state = .error
            DiagnosticsLogger.shared.log(level: "error", message: "Playback failed: \(error)")
        }
    }

    func pause() {
        player?.pause()
        state = .paused
    }

    func resume() {
        player?.play()
        state = .playing
    }

    func stop(resetPosition: Bool = true) {
        player?.stop()
        if resetPosition {
            player?.currentTime = 0
        }
        state = .idle
    }
}
