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
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    var positionUpdateHandler: ((TimeInterval) -> Void)?

    private var player: AVAudioPlayer?
    private var positionTimer: Timer?

    func loadAndPlay(track: Track, fileURL: URL, startAt: TimeInterval = 0) throws {
        do {
            if let player {
                player.stop()
            }
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.prepareToPlay()
            self.player = player
            currentTrack = track
            duration = player.duration
            if startAt > 0 {
                player.currentTime = min(startAt, player.duration)
            }
            state = .playing
            player.play()
            startPositionTimer()
        } catch {
            state = .error
            DiagnosticsLogger.shared.log(level: "error", message: "Playback failed: \(error)")
            throw error
        }
    }

    func pause() {
        player?.pause()
        state = .paused
        flushPositionUpdate()
    }

    func resume() {
        player?.play()
        state = .playing
        startPositionTimer()
    }

    func stop(resetPosition: Bool = true) {
        player?.stop()
        positionTimer?.invalidate()
        if resetPosition {
            player?.currentTime = 0
            currentTime = 0
            positionUpdateHandler?(0)
        }
        state = .idle
    }

    private func startPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, let player else { return }
            self.currentTime = player.currentTime
            self.positionUpdateHandler?(player.currentTime)
        }
    }

    private func flushPositionUpdate() {
        guard let player else { return }
        currentTime = player.currentTime
        positionUpdateHandler?(player.currentTime)
    }
}
