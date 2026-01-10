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

final class PlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var currentTrack: Track?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isStreaming: Bool = false

    var positionUpdateHandler: ((TimeInterval) -> Void)?
    var playbackEndedHandler: ((Track?) -> Void)?
    var streamingFailedHandler: ((Track?) -> Void)?

    private var player: AVAudioPlayer?
    private var positionTimer: Timer?
    private var streamPlayer: AVPlayer?
    private var streamObserver: Any?
    private var streamEndObserver: NSObjectProtocol?
    private var streamFailureObserver: NSObjectProtocol?
    private var streamStatusObserver: NSKeyValueObservation?
    private var outputDeviceListener: AudioObjectPropertyListenerBlock?
    private var nowPlayingInfo: [String: Any] = [:]

    override init() {
        super.init()
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
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            currentTrack = track
            duration = player.duration
            isStreaming = false
            if startAt > 0 {
                player.currentTime = min(startAt, player.duration)
            }
            currentTime = player.currentTime
            state = .playing
            player.play()
            startPositionTimer()
            updateNowPlayingInfo(elapsedOverride: player.currentTime)
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
        player.automaticallyWaitsToMinimizeStalling = true
        streamPlayer = player
        currentTrack = track
        isStreaming = true
        state = .playing
        if let fallbackDuration = track.durationSeconds, fallbackDuration > 0 {
            duration = fallbackDuration
        }
        if startAt > 0 {
            player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
        }
        currentTime = startAt
        addStreamObserver()
        addStreamEndObserver(for: item)
        addStreamFailureObserver(for: item)
        addStreamStatusObserver(for: item)
        player.play()
        updateNowPlayingInfo(elapsedOverride: startAt)
    }

    func pause() {
        if isStreaming {
            streamPlayer?.pause()
        } else {
            player?.pause()
        }
        state = .paused
        flushPositionUpdate()
        updateNowPlayingInfo()
    }

    func resume() {
        if isStreaming {
            streamPlayer?.play()
        } else {
            player?.play()
            startPositionTimer()
        }
        state = .playing
        updateNowPlayingInfo()
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
        nowPlayingInfo.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func seek(to time: TimeInterval) {
        guard currentTrack != nil else { return }
        let clamped = clampedTime(time)
        if isStreaming {
            streamPlayer?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        } else {
            player?.currentTime = clamped
        }
        currentTime = clamped
        positionUpdateHandler?(clamped)
        updateNowPlayingInfo(elapsedOverride: clamped)
    }

    func skip(by interval: TimeInterval) {
        let target = currentPlaybackTime() + interval
        seek(to: target)
    }

    func swapToLocalIfStreaming(trackId: UUID, fileURL: URL) throws {
        guard isStreaming, let track = currentTrack, track.id == trackId else { return }
        let resumeTime = currentPlaybackTime()
        pause()
        stopStreaming()
        try loadAndPlay(track: track, fileURL: fileURL, startAt: resumeTime)
    }

    private func startPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, let player else { return }
            self.currentTime = player.currentTime
            self.positionUpdateHandler?(player.currentTime)
            self.updateNowPlayingInfo(elapsedOverride: player.currentTime)
        }
    }

    private func flushPositionUpdate() {
        if isStreaming, let time = streamPlayer?.currentTime().seconds, time.isFinite {
            currentTime = time
            positionUpdateHandler?(time)
            updateNowPlayingInfo(elapsedOverride: time)
            return
        }
        guard let player else { return }
        currentTime = player.currentTime
        positionUpdateHandler?(player.currentTime)
        updateNowPlayingInfo(elapsedOverride: player.currentTime)
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
            updateNowPlayingInfo(elapsedOverride: seconds)
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
        streamPlayer?.replaceCurrentItem(with: nil)
        removeStreamObserver()
        removeStreamEndObserver()
        removeStreamFailureObserver()
        removeStreamStatusObserver()
        streamPlayer = nil
        isStreaming = false
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.stopCommand.isEnabled = true
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

    private func addStreamEndObserver(for item: AVPlayerItem) {
        removeStreamEndObserver()
        streamEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.handlePlaybackFinished()
        }
    }

    private func removeStreamEndObserver() {
        if let observer = streamEndObserver {
            NotificationCenter.default.removeObserver(observer)
            streamEndObserver = nil
        }
    }

    private func addStreamFailureObserver(for item: AVPlayerItem) {
        removeStreamFailureObserver()
        streamFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.handleStreamingFailure(item.error)
        }
    }

    private func removeStreamFailureObserver() {
        if let observer = streamFailureObserver {
            NotificationCenter.default.removeObserver(observer)
            streamFailureObserver = nil
        }
    }

    private func addStreamStatusObserver(for item: AVPlayerItem) {
        removeStreamStatusObserver()
        streamStatusObserver = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            guard let self else { return }
            if observed.status == .failed {
                self.handleStreamingFailure(observed.error)
            }
        }
    }

    private func removeStreamStatusObserver() {
        streamStatusObserver?.invalidate()
        streamStatusObserver = nil
    }

    private func handlePlaybackFinished() {
        let finishedTrack = currentTrack
        stop(resetPosition: true)
        playbackEndedHandler?(finishedTrack)
    }

    private func handleStreamingFailure(_ error: Error?) {
        guard isStreaming else { return }
        let failedTrack = currentTrack
        if let error {
            DiagnosticsLogger.shared.log(level: "error", message: "Streaming failed: \(error.localizedDescription)")
        } else {
            DiagnosticsLogger.shared.log(level: "error", message: "Streaming failed: unknown error")
        }
        stopStreaming()
        state = .error
        streamingFailedHandler?(failedTrack)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        handlePlaybackFinished()
    }

    private func currentPlaybackTime() -> TimeInterval {
        if isStreaming, let time = streamPlayer?.currentTime().seconds, time.isFinite {
            return time
        }
        return player?.currentTime ?? currentTime
    }

    private func clampedTime(_ time: TimeInterval) -> TimeInterval {
        let lowerBound = max(time, 0)
        let maxDuration = effectiveDuration()
        if maxDuration > 0 {
            return min(lowerBound, maxDuration)
        }
        return lowerBound
    }

    private func effectiveDuration() -> TimeInterval {
        if duration > 0 {
            return duration
        }
        if let fallback = currentTrack?.durationSeconds, fallback > 0 {
            return fallback
        }
        return 0
    }

    private func updateNowPlayingInfo(elapsedOverride: TimeInterval? = nil) {
        guard let track = currentTrack else { return }
        var info = nowPlayingInfo
        info[MPMediaItemPropertyTitle] = track.displayName
        let playbackTime = elapsedOverride ?? currentPlaybackTime()
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = state == .playing ? 1.0 : 0.0
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
