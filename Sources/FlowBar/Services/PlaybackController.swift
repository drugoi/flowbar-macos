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

struct StreamSeek {
    struct Request: Equatable {
        let id = UUID()
        let time: TimeInterval
    }

    private(set) var pending: Request?

    mutating func begin(at time: TimeInterval) -> Request {
        let request = Request(time: time)
        pending = request
        return request
    }

    @discardableResult
    mutating func clear(_ request: Request) -> Bool {
        guard pending == request else { return false }
        pending = nil
        return true
    }

    mutating func invalidate() {
        pending = nil
    }

    func skipOrigin(actualTime: TimeInterval) -> TimeInterval {
        pending?.time ?? actualTime
    }
}

final class PlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var currentTrack: Track?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isStreaming: Bool = false
    @Published private var streamTimeControlStatus: AVPlayer.TimeControlStatus = .paused
    @Published private var streamSeek = StreamSeek()
    var pendingSeekTime: TimeInterval? { streamSeek.pending?.time }
    var isBuffering: Bool {
        state == .playing && isStreaming && streamTimeControlStatus != .playing
    }
    @Published private(set) var sleepTimerRemaining: TimeInterval?
    @Published private(set) var sleepTimerDuration: TimeInterval?
    @Published private(set) var sleepTimerIsActive: Bool = false
    @Published private var playbackSpeedValue: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(playbackSpeedValue, forKey: DefaultsKey.playbackSpeed)
            applyPlaybackRate()
            updateNowPlayingInfo()
        }
    }

    var playbackSpeed: Double {
        get { playbackSpeedValue }
        set {
            let clamped = PlaybackController.availableSpeeds.contains(newValue) ? newValue : 1.0
            guard clamped != playbackSpeedValue else { return }
            playbackSpeedValue = clamped
        }
    }

    var positionUpdateHandler: ((TimeInterval) -> Void)?
    var playbackEndedHandler: ((Track?) -> Void)?
    var streamingFailedHandler: ((Track?) -> Void)?

    private enum DefaultsKey {
        static let playbackSpeed = "FlowBarPlaybackSpeed"
    }

    static let availableSpeeds: [Double] = [0.75, 1.0, 1.25, 1.5]

    private var player: AVAudioPlayer?
    private var audioMeterPlayerID: UUID?
    private var audioMeterOwner: UUID?
    private var positionTimer: Timer?
    private var streamPlayer: AVPlayer?
    private var streamServer: AACPlaybackServer?
    private var streamObserver: Any?
    private var streamEndObserver: NSObjectProtocol?
    private var streamFailureObserver: NSObjectProtocol?
    private var streamStatusObserver: NSKeyValueObservation?
    private var streamTimeControlObserver: NSKeyValueObservation?
    private var outputDeviceListener: AudioObjectPropertyListenerBlock?
    private var nowPlayingInfo: [String: Any] = [:]
    private var sleepTimer: Timer?
    private var sleepTimerEndDate: Date?

    override init() {
        let defaults: [String: Any] = [
            DefaultsKey.playbackSpeed: 1.0
        ]
        UserDefaults.standard.register(defaults: defaults)
        super.init()
        configureRemoteCommands()
        setupOutputDeviceListener()
        playbackSpeedValue = UserDefaults.standard.double(forKey: DefaultsKey.playbackSpeed)
    }

    deinit {
        sleepTimer?.invalidate()
        removeOutputDeviceListener()
    }

    func loadAndPlay(track: Track, fileURL: URL, startAt: TimeInterval = 0, autoplay: Bool = true) throws {
        do {
            stopStreaming()
            resetAudioMeter()
            player?.stop()
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.delegate = self
            player.enableRate = true
            player.rate = Float(playbackSpeed)
            player.prepareToPlay()
            self.player = player
            audioMeterPlayerID = UUID()
            currentTrack = track
            duration = player.duration
            isStreaming = false
            if startAt > 0 {
                player.currentTime = min(startAt, player.duration)
            }
            currentTime = player.currentTime
            state = autoplay ? .playing : .paused
            if autoplay {
                player.play()
                startPositionTimer()
            }
            updateNowPlayingInfo(elapsedOverride: player.currentTime)
        } catch {
            state = .error
            DiagnosticsLogger.shared.log(level: "error", message: "Playback failed: \(error)")
            throw error
        }
    }

    func streamAndPlay(track: Track, streamURL: URL, server: AACPlaybackServer? = nil, startAt: TimeInterval = 0) {
        stop(resetPosition: false)
        stopStreaming()
        streamServer = server
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
        observeStreamTimeControl(for: player)
        player.play()
        applyPlaybackRate()
        updateNowPlayingInfo(elapsedOverride: startAt)
    }

    func refreshTrackMetadata(from track: Track) {
        guard let currentTrack, currentTrack.id == track.id,
              currentTrack.title != track.title || currentTrack.durationSeconds != track.durationSeconds else { return }
        self.currentTrack = track
        if state != .idle {
            updateNowPlayingInfo()
        }
    }

    func pause() {
        resetAudioMeter()
        if isStreaming {
            streamPlayer?.pause()
        } else {
            player?.pause()
        }
        state = .paused
        if isStreaming, streamTimeControlStatus != .paused {
            streamTimeControlStatus = .paused
        }
        positionTimer?.invalidate()
        positionTimer = nil
        flushPositionUpdate()
        updateNowPlayingInfo()
    }

    func resume() {
        if isStreaming {
            streamPlayer?.play()
        } else {
            if state != .playing, player != nil {
                audioMeterPlayerID = UUID()
            }
            player?.play()
            startPositionTimer()
        }
        state = .playing
        applyPlaybackRate()
        updateNowPlayingInfo()
    }

    func stop(resetPosition: Bool = true) {
        resetAudioMeter()
        cancelPendingStreamSeek()
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
        stopStreaming()
        nowPlayingInfo.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func discardTrack(_ id: UUID) {
        guard currentTrack?.id == id else { return }
        stop(resetPosition: false)
        stopStreaming()
        cancelSleepTimer()
        player = nil
        audioMeterPlayerID = nil
        currentTrack = nil
        currentTime = 0
        duration = 0
    }

    /// Seeks to a target time in seconds, clamped to the current track's duration bounds.
    /// - Parameter time: The desired playback position in seconds.
    func seek(to time: TimeInterval) {
        guard let trackId = currentTrack?.id, time.isFinite else { return }
        let clamped = clampedTime(time)
        if isStreaming {
            guard let streamPlayer, let item = streamPlayer.currentItem else { return }
            let request = streamSeek.begin(at: clamped)
            let targetTime = CMTime(seconds: clamped, preferredTimescale: 600)
            streamPlayer.seek(to: targetTime) { [weak self, weak item] finished in
                DispatchQueue.main.async {
                    guard let self, let item,
                          self.currentTrack?.id == trackId,
                          self.streamPlayer?.currentItem === item,
                          self.streamSeek.pending == request else { return }
                    let sample = self.streamPlayer?.currentTime().seconds
                    let fallback = finished ? request.time : self.currentTime
                    let resolved = sample.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? fallback
                    self.currentTime = self.clampedTime(resolved)
                    if finished {
                        self.positionUpdateHandler?(self.currentTime)
                        self.updateNowPlayingInfo(elapsedOverride: self.currentTime)
                    }
                    self.streamSeek.clear(request)
                }
            }
        } else {
            player?.currentTime = clamped
            currentTime = clamped
            positionUpdateHandler?(clamped)
            updateNowPlayingInfo(elapsedOverride: clamped)
        }
    }

    /// Skips the current playback position by the provided interval in seconds.
    /// - Parameter interval: The number of seconds to skip forward or backward.
    func skip(by interval: TimeInterval) {
        let target = streamSeek.skipOrigin(actualTime: currentPlaybackTime()) + interval
        seek(to: target)
    }

    func startSleepTimer(duration: TimeInterval) {
        sleepTimer?.invalidate()
        sleepTimerDuration = duration
        sleepTimerEndDate = Date().addingTimeInterval(duration)
        updateSleepTimerRemaining()
        DiagnosticsLogger.shared.log(level: "info", message: "Sleep timer started: \(duration) seconds")
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateSleepTimerRemaining()
        }
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerEndDate = nil
        sleepTimerRemaining = nil
        sleepTimerDuration = nil
        sleepTimerIsActive = false
        DiagnosticsLogger.shared.log(level: "info", message: "Sleep timer cancelled")
    }

    func swapToLocalIfStreaming(trackId: UUID, fileURL: URL) throws {
        guard isStreaming, let track = currentTrack, track.id == trackId else { return }
        let autoplay = state == .playing
        let resumeTime = streamSeek.skipOrigin(actualTime: currentPlaybackTime())
        pause()
        stopStreaming()
        try loadAndPlay(track: track, fileURL: fileURL, startAt: resumeTime, autoplay: autoplay)
    }

    func isStreaming(from cache: AACRangeCache) -> Bool {
        isStreaming && streamServer?.cache === cache
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
        guard pendingSeekTime == nil else { return }
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
            if let item = streamPlayer?.currentItem {
                let duration = item.duration.seconds
                if duration.isFinite, duration > 0, duration != self.duration {
                    self.duration = duration
                }
            }
            let seconds = time.seconds
            guard pendingSeekTime == nil, seconds.isFinite else { return }
            currentTime = seconds
            positionUpdateHandler?(seconds)
            updateNowPlayingInfo(elapsedOverride: seconds)
        }
    }

    private func removeStreamObserver() {
        if let observer = streamObserver {
            streamPlayer?.removeTimeObserver(observer)
            streamObserver = nil
        }
    }

    private func stopStreaming() {
        cancelPendingStreamSeek()
        streamPlayer?.pause()
        streamPlayer?.replaceCurrentItem(with: nil)
        removeStreamObserver()
        removeStreamEndObserver()
        removeStreamFailureObserver()
        removeStreamStatusObserver()
        streamPlayer = nil
        streamServer = nil
        isStreaming = false
        stopObservingStreamTimeControl()
    }

    private func observeStreamTimeControl(for player: AVPlayer) {
        streamTimeControlObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async { [weak self, weak player] in
                guard let self, let player, self.isStreaming, self.streamPlayer === player else { return }
                let status = player.timeControlStatus
                if self.streamTimeControlStatus != status {
                    self.streamTimeControlStatus = status
                }
            }
        }
    }

    private func stopObservingStreamTimeControl() {
        streamTimeControlObserver = nil
        if streamTimeControlStatus != .paused {
            streamTimeControlStatus = .paused
        }
    }

    private func cancelPendingStreamSeek() {
        guard pendingSeekTime != nil else { return }
        streamSeek.invalidate()
        streamPlayer?.currentItem?.cancelPendingSeeks()
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
            guard observed.status == .failed else { return }
            DispatchQueue.main.async { [weak self, weak observed] in
                guard let self, let observed, self.streamPlayer?.currentItem === observed else { return }
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

    func currentPlaybackTime() -> TimeInterval {
        let liveTime = isStreaming ? streamPlayer?.currentTime().seconds : player?.currentTime
        if let time = liveTime, time.isFinite, time >= 0 {
            return time
        }
        return currentTime.isFinite ? max(currentTime, 0) : 0
    }

    var audioMeterSourceID: UUID? {
        guard state == .playing, !isStreaming, player?.isPlaying == true else { return nil }
        return audioMeterPlayerID
    }

    func startAudioMeter(for source: UUID) -> UUID? {
        guard source == audioMeterSourceID, let player, player.numberOfChannels > 0 else { return nil }
        let owner = UUID()
        audioMeterOwner = owner
        player.isMeteringEnabled = true
        return owner
    }

    func stopAudioMeter(owner: UUID) {
        guard owner == audioMeterOwner else { return }
        resetAudioMeter()
    }

    func averageAudioPower(owner: UUID) -> Double? {
        guard owner == audioMeterOwner, audioMeterSourceID != nil, let player else { return nil }
        player.updateMeters()
        var loudestChannel: Double?
        for channel in 0..<player.numberOfChannels {
            let power = Double(player.averagePower(forChannel: channel))
            guard power.isFinite else { continue }
            loudestChannel = max(loudestChannel ?? power, power)
        }
        return loudestChannel
    }

    private func resetAudioMeter() {
        if audioMeterOwner != nil {
            player?.isMeteringEnabled = false
            audioMeterOwner = nil
        }
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
        info[MPMediaItemPropertyTitle] = track.title
        if elapsedOverride != nil || pendingSeekTime == nil {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedOverride ?? currentPlaybackTime()
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = state == .playing ? playbackSpeed : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = playbackSpeed
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateSleepTimerRemaining() {
        guard let endDate = sleepTimerEndDate else {
            sleepTimerRemaining = nil
            sleepTimerIsActive = false
            return
        }
        let remaining = max(0, endDate.timeIntervalSinceNow)
        sleepTimerRemaining = remaining
        sleepTimerIsActive = remaining > 0
        if remaining <= 0 {
            handleSleepTimerExpired()
        }
    }

    private func handleSleepTimerExpired() {
        DiagnosticsLogger.shared.log(level: "info", message: "Sleep timer expired")
        stop()
        cancelSleepTimer()
    }

    private func applyPlaybackRate() {
        let rate = Float(playbackSpeedValue)
        if isStreaming {
            streamPlayer?.rate = rate
            if state != .playing {
                streamPlayer?.pause()
            }
        } else {
            player?.enableRate = true
            player?.rate = rate
        }
    }
}
