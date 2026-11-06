import Testing

@testable import FTMSKit

/// Trames réelles du tapis FitShow FS-37FBED, relevées avec le POC Python.
struct TreadmillDataTests {
    @Test func decodesRealFrame() throws {
        let frame = try bytes("8c 05 c8 00 51 02 00 00 00 00 00 29 00 ff ff ff 00 36 04")
        let data = try TreadmillData(decoding: frame)

        #expect(data.flags == 0x058C)
        #expect(data.speedKmh == 2.0)
        #expect(data.totalDistanceMeters == 593)
        #expect(data.inclinationPercent == 0)
        #expect(data.rampAngleDegrees == 0)
        #expect(data.totalEnergyKcal == 41)
        #expect(data.energyPerHourKcal == nil)
        #expect(data.energyPerMinuteKcal == nil)
        #expect(data.heartRateBPM == 0)
        #expect(data.elapsedSeconds == 1078)
        #expect(data.extraBytes == 0)
    }

    @Test func decodesFrameAfterSpeedChange() throws {
        let data = try TreadmillData(
            decoding: try bytes("8c 05 e6 00 08 00 00 00 00 00 00 00 00 ff ff ff 00 11 00")
        )
        #expect(data.speedKmh == 2.3)
        #expect(data.totalDistanceMeters == 8)
        #expect(data.elapsedSeconds == 17)
    }

    @Test func reportsExtraBytes() throws {
        // Trame de 20 octets relevée avec LightBlue : un octet de plus que n'en annoncent les flags.
        let frame = try bytes("8c 05 c8 00 1c 01 00 00 00 00 00 00 14 00 ff ff ff 00 0b 02")
        #expect(try TreadmillData(decoding: frame).extraBytes == 1)
    }

    @Test func rejectsTruncatedFrame() throws {
        let frame = try bytes("8c 05 c8 00 51 02")
        #expect(throws: FTMSError.truncated(expectedAtLeast: 7, actual: 6)) {
            try TreadmillData(decoding: frame)
        }
    }

    @Test func rejectsEmptyFrame() {
        #expect(throws: FTMSError.self) {
            try TreadmillData(decoding: [])
        }
    }

    @Test func moreDataFlagHidesSpeed() throws {
        let data = try TreadmillData(decoding: [0x01, 0x00])
        #expect(data.speedKmh == nil)
        #expect(data.extraBytes == 0)
    }

    @Test func decodesEveryOptionalField() throws {
        let frame: [UInt8] = [
            0xFE, 0x1F,  // tous les champs sauf « More Data »
            0xF4, 0x01,  // vitesse 5,00
            0x2C, 0x01,  // vitesse moyenne 3,00
            0x10, 0x27, 0x00,  // distance 10 000 m
            0x0F, 0x00,  // inclinaison 1,5 %
            0xFF, 0x7F,  // rampe non disponible
            0x64, 0x00,  // dénivelé positif 10,0 m
            0x32, 0x00,  // dénivelé négatif 5,0 m
            0x0C,  // allure 1,2 km/min
            0x0A,  // allure moyenne 1,0 km/min
            0x2A, 0x00,  // 42 kcal
            0xC8, 0x00,  // 200 kcal/h
            0x03,  // 3 kcal/min
            0x78,  // 120 bpm
            0x2D,  // 4,5 MET
            0x3C, 0x00,  // 60 s écoulées
            0x1E, 0x00,  // 30 s restantes
            0xF6, 0xFF,  // force -10 N
            0x96, 0x00,  // 150 W
        ]
        let data = try TreadmillData(decoding: frame)
        #expect(data.speedKmh == 5)
        #expect(data.averageSpeedKmh == 3)
        #expect(data.totalDistanceMeters == 10_000)
        #expect(data.inclinationPercent == 1.5)
        #expect(data.rampAngleDegrees == nil)
        #expect(data.positiveElevationGainMeters == 10)
        #expect(data.negativeElevationGainMeters == 5)
        #expect(data.instantaneousPaceKmPerMinute == 1.2)
        #expect(data.averagePaceKmPerMinute == 1)
        #expect(data.totalEnergyKcal == 42)
        #expect(data.energyPerHourKcal == 200)
        #expect(data.energyPerMinuteKcal == 3)
        #expect(data.heartRateBPM == 120)
        #expect(data.metabolicEquivalent == 4.5)
        #expect(data.elapsedSeconds == 60)
        #expect(data.remainingSeconds == 30)
        #expect(data.forceOnBeltNewtons == -10)
        #expect(data.powerWatts == 150)
        #expect(data.extraBytes == 0)
    }

    @Test func formatsHex() {
        #expect(hexString([0x80, 0x00, 0x01, 0xAB]) == "80 00 01 ab")
    }
}

/// Convertit « 8c 05 c8 » en octets.
func bytes(_ hex: String) throws -> [UInt8] {
    try hex.split(separator: " ").map { pair in
        try #require(UInt8(pair, radix: 16), "octet illisible : \(pair)")
    }
}
