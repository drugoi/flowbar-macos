import Foundation
import AVFoundation
import Combine
import MediaPlayer
import CoreAudio

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
    @Published private(set) var isStreaming: Bool = false

    var positionUpdateHandler: ((TimeInterval) -> Void)?

    private var player: AVAudioPlayer?
    private var positionTimer: Timer?
    private var streamPlayer: AVPlayer?
    private var streamObserver: Any?
    private var outputDeviceListener: AudioObjectPropertyListenerBlock?

    init() {
        configureRemoteCommands()
        setupOutputDeviceListener()
    }

    deinit {
        removeOutputDeviceListener()
    }

    func loadAndPlay(track: Track, fileURL: URL, startAt: TimeInterval = 0) throws {
        do {
            stopStreaming()
            player?.stop()
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.prepareToPlay()
            self.player = player
            currentTrack = track
            duration = player.duration
            isStreaming = false
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

    func streamAndPlay(track: Track, streamURL: URL, startAt: TimeInterval = 0) {
        stop(resetPosition: false)
        stopStreaming()
        let item = AVPlayerItem(url: streamURL)
        let player = AVPlayer(playerItem: item)
        streamPlayer = player
        currentTrack = track
        isStreaming = true
        state = .playing
        if startAt > 0 {
            player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
        }
        addStreamObserver()
        player.play()
    }

    func pause() {
        if isStreaming {
            streamPlayer?.pause()
        } else {
            player?.pause()
        }
        state = .paused
        flushPositionUpdate()
    }

    func resume() {
        if isStreaming {
            streamPlayer?.play()
        } else {
            player?.play()
            startPositionTimer()
        }
        state = .playing
    }

    func stop(resetPosition: Bool = true) {
        player?.stop()
        streamPlayer?.pause()
        positionTimer?.invalidate()
        removeStreamObserver()
        if resetPosition {
            player?.currentTime = 0
            currentTime = 0
            positionUpdateHandler?(0)
        }
        state = .idle
        isStreaming = false
    }

    func swapToLocalIfStreaming(trackId: UUID, fileURL: URL) throws {
        guard isStreaming, let track = currentTrack, track.id == trackId else { return }
        let resumeTime = currentTime
        stopStreaming()
        try loadAndPlay(track: track, fileURL: fileURL, startAt: resumeTime)
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
        if isStreaming, let time = streamPlayer?.currentTime().seconds, time.isFinite {
            currentTime = time
            positionUpdateHandler?(time)
            return
        }
        guard let player else { return }
        currentTime = player.currentTime
        positionUpdateHandler?(player.currentTime)
    }

    private func addStreamObserver() {
        removeStreamObserver()
        let interval = CMTime(seconds: 1, preferredTimescale: 2)
        streamObserver = streamPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            currentTime = seconds
            positionUpdateHandler?(seconds)
            if let item = streamPlayer?.currentItem {
                let duration = item.duration.seconds
                if duration.isFinite, duration > 0 {
                    self.duration = duration
                }
            }
        }
    }

    private func removeStreamObserver() {
        if let observer = streamObserver {
            streamPlayer?.removeTimeObserver(observer)
            streamObserver = nil
        }
    }

    private func stopStreaming() {
        streamPlayer?.pause()
        removeStreamObserver()
        streamPlayer = nil
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.state == .playing {
                self.pause()
            } else {
                self.resume()
            }
            return .success
        }
        commandCenter.stopCommand.addTarget { [weak self] _ in
            self?.stop()
            return .success
        }
    }

    private func setupOutputDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self, self.state == .playing else { return }
                self.pause()
            }
        }
        outputDeviceListener = block
        AudioObjectAddPropertyListenerBlock(systemObject, &address, DispatchQueue.main, block)
    }

    private func removeOutputDeviceListener() {
        guard let block = outputDeviceListener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectRemovePropertyListenerBlock(systemObject, &address, DispatchQueue.main, block)
        outputDeviceListener = nil
    }
}
