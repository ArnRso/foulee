import Foundation
import Testing

@testable import FTMSKit

struct SessionRecorderTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Trame Treadmill Data aux flags du tapis réel (`0x058C`).
    private func frame(speed: Double, distance: Int, kcal: Int, elapsed: Int) throws
        -> TreadmillData
    {
        var bytes: [UInt8] = [0x8C, 0x05]
        bytes += littleEndian(Int((speed * 100).rounded()), size: 2)
        bytes += littleEndian(distance, size: 3)
        bytes += [0x00, 0x00, 0x00, 0x00]
        bytes += littleEndian(kcal, size: 2)
        bytes += [0xFF, 0xFF, 0xFF, 0x00]
        bytes += littleEndian(elapsed, size: 2)
        return try TreadmillData(decoding: bytes)
    }

    private func littleEndian(_ value: Int, size: Int) -> [UInt8] {
        (0..<size).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }

    private func record(
        _ recorder: inout SessionRecorder,
        second: Int,
        speed: Double,
        distance: Int,
        kcal: Int = 0,
        elapsed: Int,
    ) throws -> TreadmillSession? {
        recorder.record(
            try frame(speed: speed, distance: distance, kcal: kcal, elapsed: elapsed),
            at: start.addingTimeInterval(Double(second)),
            deviceName: "FS-37FBED",
        )
    }

    @Test func ignoresStoppedBelt() throws {
        var recorder = SessionRecorder()
        #expect(try record(&recorder, second: 0, speed: 0, distance: 0, elapsed: 0) == nil)
        #expect(recorder.current == nil)
    }

    @Test func recordsSessionUntilStop() throws {
        var recorder = SessionRecorder()
        _ = try record(&recorder, second: 0, speed: 1, distance: 0, elapsed: 0)
        _ = try record(&recorder, second: 60, speed: 2.5, distance: 30, kcal: 2, elapsed: 60)
        _ = try record(&recorder, second: 120, speed: 3, distance: 80, kcal: 5, elapsed: 120)

        let stopped = recorder.record(.stoppedByUser, at: start.addingTimeInterval(121))
        let session = try #require(stopped)
        #expect(recorder.current == nil)
        #expect(session.events == [.init(offsetSeconds: 121, kind: .stopped)])
        #expect(session.deviceName == "FS-37FBED")
        #expect(session.startDate == start)
        #expect(session.endDate == start.addingTimeInterval(120))
        #expect(session.distanceMeters == 80)
        #expect(session.elapsedSeconds == 120)
        #expect(session.energyKcal == 5)
        #expect(session.maximumSpeedKmh == 3)
        #expect(session.averageSpeedKmh == 2.4)
        #expect(session.samples.count == 3)
        #expect(!session.isInterrupted)
        #expect(session.isWorthKeeping)
    }

    @Test func pauseKeepsSessionGoing() throws {
        var recorder = SessionRecorder()
        _ = try record(&recorder, second: 0, speed: 2, distance: 0, elapsed: 0)
        #expect(recorder.record(.pausedByUser, at: start.addingTimeInterval(29)) == nil)
        _ = try record(&recorder, second: 30, speed: 0, distance: 16, elapsed: 30)
        #expect(recorder.record(.startedOrResumedByUser, at: start.addingTimeInterval(75)) == nil)
        _ = try record(&recorder, second: 90, speed: 1, distance: 20, elapsed: 45)
        recorder.note(.targetSpeed, speedKmh: 2.5, at: start.addingTimeInterval(95))

        let finished = recorder.finish(interrupted: true)
        let session = try #require(finished)
        #expect(session.distanceMeters == 20)
        #expect(session.elapsedSeconds == 45)
        #expect(session.isInterrupted)
        #expect(
            session.events == [
                .init(offsetSeconds: 29, kind: .paused),
                .init(offsetSeconds: 75, kind: .started),
                .init(offsetSeconds: 95, kind: .targetSpeed, speedKmh: 2.5),
            ]
        )
    }

    @Test func counterResetEndsSession() throws {
        var recorder = SessionRecorder()
        _ = try record(&recorder, second: 0, speed: 2, distance: 0, elapsed: 0)
        _ = try record(&recorder, second: 600, speed: 2, distance: 330, elapsed: 600)

        // Arrêt à la télécommande sans statut reçu : la trame suivante repart de zéro.
        let finished = try #require(
            try record(&recorder, second: 601, speed: 0, distance: 0, elapsed: 0)
        )
        #expect(finished.distanceMeters == 330)
        #expect(recorder.current == nil)
    }

    @Test func zeroFrameAfterStopDoesNotOpenSession() throws {
        var recorder = SessionRecorder()
        _ = try record(&recorder, second: 0, speed: 2, distance: 50, elapsed: 90)
        #expect(recorder.record(.stoppedByUser, at: start) != nil)
        #expect(try record(&recorder, second: 1, speed: 0, distance: 0, elapsed: 0) == nil)
        #expect(recorder.record(.stoppedByUser, at: start) == nil)
    }

    @Test func sessionStartedBeforeConnectionIsBackdated() throws {
        var recorder = SessionRecorder()
        _ = try record(&recorder, second: 0, speed: 2, distance: 593, elapsed: 1078)
        let session = try #require(recorder.current)
        #expect(session.startDate == start.addingTimeInterval(-1078))
        #expect(session.distanceMeters == 593)
    }

    @Test func shortSessionIsNotKept() throws {
        var recorder = SessionRecorder()
        _ = try record(&recorder, second: 0, speed: 1, distance: 0, elapsed: 0)
        _ = try record(&recorder, second: 5, speed: 1, distance: 1, elapsed: 5)
        let stopped = recorder.record(.stoppedByUser, at: start)
        let session = try #require(stopped)
        #expect(!session.isWorthKeeping)
    }

    @Test func survivesJSONRoundTrip() throws {
        var recorder = SessionRecorder()
        _ = try record(&recorder, second: 0, speed: 2, distance: 0, elapsed: 0)
        _ = try record(&recorder, second: 60, speed: 2.5, distance: 40, kcal: 3, elapsed: 60)
        let finished = recorder.finish(interrupted: false)
        let session = try #require(finished)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            TreadmillSession.self,
            from: try encoder.encode(session),
        )
        #expect(decoded == session)
    }
}
