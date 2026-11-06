import Foundation
import Testing

@testable import FTMSKit

struct SpeedChangeTests {
    private func session(speeds: [(Double, Double)]) -> TreadmillSession {
        TreadmillSession(
            startDate: .distantPast,
            endDate: .distantPast,
            elapsedSeconds: 0,
            distanceMeters: 0,
            maximumSpeedKmh: 0,
            samples: speeds.map { offset, speed in
                .init(offsetSeconds: offset, speedKmh: speed, distanceMeters: 0)
            },
        )
    }

    @Test func steadySpeedHasNoChange() {
        #expect(session(speeds: [(0, 2), (1, 2), (2, 2)]).speedChanges.isEmpty)
    }

    @Test func mergesRampIntoOneChange() {
        let changes = session(speeds: [
            (0, 2), (60, 2), (61, 2.2), (62, 2.4), (63, 2.5), (64, 2.5),
        ])
        .speedChanges
        #expect(changes == [SpeedChange(offsetSeconds: 60, fromKmh: 2, toKmh: 2.5)])
        #expect(changes.first?.deltaKmh == 0.5)
    }

    @Test func separatesDistantChanges() {
        let changes = session(speeds: [(0, 2), (1, 2.5), (100, 2.5), (101, 3)]).speedChanges
        #expect(
            changes == [
                SpeedChange(offsetSeconds: 0, fromKmh: 2, toKmh: 2.5),
                SpeedChange(offsetSeconds: 100, fromKmh: 2.5, toKmh: 3),
            ]
        )
    }

    @Test func separatesDirectionReversal() {
        let changes = session(speeds: [(0, 2), (1, 2.5), (2, 2.1)]).speedChanges
        #expect(changes.map(\.deltaKmh) == [0.5, -0.4])
    }

    @Test func pauseIsChangeToZero() {
        let changes = session(speeds: [(0, 3), (1, 1.5), (2, 0), (40, 0), (41, 1)]).speedChanges
        #expect(
            changes == [
                SpeedChange(offsetSeconds: 0, fromKmh: 3, toKmh: 0),
                SpeedChange(offsetSeconds: 40, fromKmh: 0, toKmh: 1),
            ]
        )
    }
}

struct SessionStatisticsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ day: Int, month: Int = 11, hour: Int = 10) throws -> Date {
        try #require(
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))
        )
    }

    private func session(on date: Date, meters: Int, seconds: Int, kcal: Int? = 10)
        -> SessionSummary
    {
        TreadmillSession(
            startDate: date,
            endDate: date.addingTimeInterval(Double(seconds)),
            elapsedSeconds: seconds,
            distanceMeters: meters,
            energyKcal: kcal,
            maximumSpeedKmh: 3,
        )
        .summary
    }

    @Test func groupsByDayIncludingEmptyDays() throws {
        let sessions = [
            session(on: try date(4), meters: 1000, seconds: 1200),
            session(on: try date(6, hour: 8), meters: 500, seconds: 600),
            session(on: try date(6, hour: 18), meters: 1500, seconds: 1800, kcal: nil),
        ]
        let days = SessionStatistics.summaries(
            of: sessions,
            by: .day,
            count: 3,
            endingAt: try date(6, hour: 23),
            calendar: calendar,
        )
        #expect(
            days.map(\.start) == [
                try date(4, hour: 0), try date(5, hour: 0), try date(6, hour: 0),
            ]
        )
        #expect(days.map(\.sessionCount) == [1, 0, 2])
        #expect(days.map(\.distanceMeters) == [1000, 0, 2000])
        #expect(days[2].elapsedSeconds == 2400)
        #expect(days[2].energyKcal == 10)
        #expect(days[2].averageSpeedKmh == 3)
    }

    @Test func groupsByWeekStartingMonday() throws {
        // 2 novembre 2026 : lundi.
        let sessions = [
            session(on: try date(1), meters: 100, seconds: 100),
            session(on: try date(2), meters: 200, seconds: 100),
            session(on: try date(8), meters: 300, seconds: 100),
        ]
        let weeks = SessionStatistics.summaries(
            of: sessions,
            by: .week,
            count: 2,
            endingAt: try date(6),
            calendar: calendar,
        )
        #expect(weeks.map(\.start) == [try date(26, month: 10, hour: 0), try date(2, hour: 0)])
        #expect(weeks.map(\.distanceMeters) == [100, 500])
    }

    @Test func groupsByMonthAndIgnoresOlderSessions() throws {
        let sessions = [
            session(on: try date(15, month: 8), meters: 9999, seconds: 100),
            session(on: try date(20, month: 10), meters: 700, seconds: 100),
            session(on: try date(3), meters: 300, seconds: 100),
        ]
        let months = SessionStatistics.summaries(
            of: sessions,
            by: .month,
            count: 2,
            endingAt: try date(6),
            calendar: calendar,
        )
        #expect(months.map(\.distanceMeters) == [700, 300])
    }

    @Test func totalsEverything() throws {
        let total = SessionStatistics.total(of: [
            session(on: try date(1), meters: 1000, seconds: 600),
            session(on: try date(2), meters: 2000, seconds: 1200),
        ])
        #expect(total.sessionCount == 2)
        #expect(total.distanceMeters == 3000)
        #expect(total.averageSpeedKmh == 6)
    }
}

struct SessionFormatTests {
    @Test func readsVersionOneFileWithoutEvents() throws {
        let json = """
            {
              "deviceName" : "FS-37FBED",
              "distanceMeters" : 120,
              "elapsedSeconds" : 90,
              "endDate" : "2026-11-06T14:17:53Z",
              "energyKcal" : 8,
              "formatVersion" : 1,
              "id" : "0E0F8C55-5C1C-4D58-9D86-7C1F4B1A3E7A",
              "isInterrupted" : false,
              "maximumSpeedKmh" : 2.5,
              "samples" : [
                { "distanceMeters" : 120, "elapsedSeconds" : 90, "offsetSeconds" : 90, "speedKmh" : 2.5 }
              ],
              "startDate" : "2026-11-06T14:16:23Z"
            }
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(TreadmillSession.self, from: Data(json.utf8))
        #expect(session.formatVersion == 1)
        #expect(session.events.isEmpty)
        #expect(session.samples.count == 1)
        #expect(session.distanceMeters == 120)

        // Réécrit au format actuel : relevés en colonnes.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let rewritten = try decoder.decode(
            TreadmillSession.self,
            from: try encoder.encode(session),
        )
        #expect(rewritten.formatVersion == TreadmillSession.formatVersion)
        #expect(rewritten.samples == session.samples)
    }

    @Test func writesSamplesAsColumns() throws {
        let samples = (0..<3600).map { second in
            TreadmillSession.Sample(
                offsetSeconds: Double(second),
                speedKmh: 3.5,
                distanceMeters: second,
                energyKcal: second / 20,
                elapsedSeconds: second,
            )
        }
        let session = TreadmillSession(
            startDate: .distantPast,
            endDate: .distantPast,
            elapsedSeconds: 3600,
            distanceMeters: 3500,
            maximumSpeedKmh: 3.5,
            samples: samples,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(session)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"sampleColumns\""))
        #expect(!json.contains("\"samples\""))
        // Une heure de relevés : bien moins de 200 Ko (environ 600 Ko dans l'ancien format).
        #expect(data.count < 200_000)
        #expect(try JSONDecoder().decode(TreadmillSession.self, from: data).samples == samples)
    }

    @Test func rejectsColumnsOfDifferentLengths() {
        let json = """
            {
              "distanceMeters" : 0, "elapsedSeconds" : 0, "endDate" : 0, "formatVersion" : 3,
              "id" : "0E0F8C55-5C1C-4D58-9D86-7C1F4B1A3E7A", "isInterrupted" : false,
              "maximumSpeedKmh" : 0, "startDate" : 0,
              "sampleColumns" : {
                "offsetSeconds" : [0, 1], "speedKmh" : [1], "distanceMeters" : [0, 1],
                "energyKcal" : [null, null], "elapsedSeconds" : [0, 1]
              }
            }
            """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TreadmillSession.self, from: Data(json.utf8))
        }
    }
}
