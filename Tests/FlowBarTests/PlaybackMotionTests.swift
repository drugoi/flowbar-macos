import AVFAudio
import XCTest
@testable import FlowBar

final class PlaybackMotionTests: XCTestCase {
    func testHoldingScrubberRetainsVisiblePositionWithoutCommitting() {
        var drag = ScrubberDrag()
        drag.begin(at: 28.25)
        XCTAssertEqual(drag.position, 28.25)
        XCTAssertNil(drag.end())
        XCTAssertNil(drag.position)

        drag.begin(at: 29.5)
        drag.move(to: 35)
        XCTAssertEqual(drag.end(), 35)
        XCTAssertNil(drag.end())
    }

    func testGrooveResponseNormalizesSoundAndRespectsVisualLimits() {
        for (decibels, expected) in [(-60.0, 0.0), (-45, 0), (-27.5, 0.5), (-10, 1), (0, 1)] {
            XCTAssertEqual(GrooveResponse.normalizedLevel(decibels: decibels), expected, accuracy: 0.0001)
        }
        XCTAssertEqual(GrooveResponse.opacity(for: 0, enabled: true), 0.130, accuracy: 0.0001)
        XCTAssertEqual(GrooveResponse.opacity(for: 2, enabled: true), 0.165, accuracy: 0.0001)
        XCTAssertEqual(GrooveResponse.opacity(for: 1, enabled: false), 0.130, accuracy: 0.0001)
    }

    func testGrooveResponseBrightensFasterThanItFadesAndSettlesInSilence() {
        let attack = GrooveResponse.smoothedLevel(previous: 0.5, decibels: -10, elapsed: 0.05)
        let release = GrooveResponse.smoothedLevel(previous: 0.5, decibels: -60, elapsed: 0.05)
        XCTAssertGreaterThan(attack - 0.5, 0.5 - release)

        let settled = (0..<100).reduce(1.0) { level, _ in
            GrooveResponse.smoothedLevel(previous: level, decibels: -60, elapsed: 0.05)
        }
        XCTAssertEqual(settled, 0)
    }

    func testStreamingSeekIgnoresSupersededAndInvalidatedRequests() {
        var seek = StreamSeek()
        let first = seek.begin(at: 20)
        let second = seek.begin(at: 35)

        XCTAssertFalse(seek.clear(first))
        XCTAssertEqual(seek.pending?.time, 35)
        XCTAssertTrue(seek.clear(second))
        XCTAssertNil(seek.pending)

        let oldTrack = seek.begin(at: 90)
        seek.invalidate()
        XCTAssertFalse(seek.clear(oldTrack))
        XCTAssertNil(seek.pending)
    }

    func testRepeatedSkipStartsAtPendingPositionAndFailureClearsIt() {
        var seek = StreamSeek()
        XCTAssertEqual(seek.skipOrigin(actualTime: 6), 6)
        _ = seek.begin(at: 21)
        let latest = seek.begin(at: seek.skipOrigin(actualTime: 6) + 15)
        XCTAssertEqual(latest.time, 36)
        XCTAssertTrue(seek.clear(latest))
        XCTAssertEqual(seek.skipOrigin(actualTime: 7), 7)
    }

    @MainActor
    func testReadingLiveTimeDoesNotPublishOrSavePlaybackPosition() async throws {
        let fileURL = try makeSilentAudio()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let controller = PlaybackController()
        defer { controller.stop(resetPosition: false) }
        var checkpoints: [TimeInterval] = []
        controller.positionUpdateHandler = { checkpoints.append($0) }
        let track = Track.makeNew(sourceURL: fileURL, videoId: "fixture", displayName: "Fixture")
        try controller.loadAndPlay(track: track, fileURL: fileURL, startAt: 1)
        let checkpoint = controller.currentTime

        let deadline = Date().addingTimeInterval(1)
        while controller.currentPlaybackTime() <= checkpoint, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertGreaterThan(controller.currentPlaybackTime(), checkpoint)
        XCTAssertEqual(controller.currentTime, checkpoint)
        XCTAssertTrue(checkpoints.isEmpty)

        let source = try XCTUnwrap(controller.audioMeterSourceID)
        let firstMeter = try XCTUnwrap(controller.startAudioMeter(for: source))
        controller.pause()
        XCTAssertEqual(checkpoints.count, 1)
        XCTAssertEqual(controller.currentPlaybackTime(), controller.currentTime, accuracy: 0.02)
        XCTAssertNil(controller.averageAudioPower(owner: firstMeter))

        controller.resume()
        let resumedSource = try XCTUnwrap(controller.audioMeterSourceID)
        XCTAssertNotEqual(resumedSource, source)
        let newMeter = try XCTUnwrap(controller.startAudioMeter(for: resumedSource))
        controller.stopAudioMeter(owner: firstMeter)
        XCTAssertNotNil(controller.averageAudioPower(owner: newMeter))
        controller.stopAudioMeter(owner: newMeter)
        XCTAssertNil(controller.averageAudioPower(owner: newMeter))
    }

    @MainActor
    func testStreamingBuffersUntilPlaybackStartsAndClearsOnPauseOrStop() async throws {
        let fileURL = try makeSilentAudio()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let controller = PlaybackController()
        defer { controller.stop(resetPosition: false) }
        let track = Track.makeNew(sourceURL: fileURL, videoId: "fixture", displayName: "Fixture")

        controller.streamAndPlay(track: track, streamURL: fileURL)
        XCTAssertTrue(controller.isBuffering)
        XCTAssertEqual(controller.state, .playing)

        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(3)
        while controller.isBuffering, clock.now < deadline {
            try await clock.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(controller.isBuffering)
        XCTAssertEqual(controller.state, .playing)

        controller.pause()
        XCTAssertFalse(controller.isBuffering)
        XCTAssertEqual(controller.state, .paused)

        controller.streamAndPlay(track: track, streamURL: fileURL)
        XCTAssertTrue(controller.isBuffering)
        controller.stop()
        try await clock.sleep(for: .milliseconds(50))
        XCTAssertFalse(controller.isBuffering)
        XCTAssertEqual(controller.state, .idle)
    }

    private func makeSilentAudio() throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 132_300))
        buffer.frameLength = buffer.frameCapacity
        let samples = try XCTUnwrap(buffer.floatChannelData?.pointee)
        for index in 0..<Int(buffer.frameLength) {
            samples[index] = 0
        }
        try AVAudioFile(forWriting: fileURL, settings: format.settings).write(from: buffer)
        return fileURL
    }
}
