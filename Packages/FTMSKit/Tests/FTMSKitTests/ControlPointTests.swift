import Testing

@testable import FTMSKit

struct ControlPointTests {
    @Test(
        arguments: [
            (ControlPointCommand.requestControl, [UInt8]([0x00])),
            (.reset, [0x01]),
            (.startOrResume, [0x07]),
            (.stop, [0x08, 0x01]),
            (.pause, [0x08, 0x02]),
            (.setTargetSpeed(kmh: 3), [0x02, 0x2C, 0x01]),
            (.setTargetSpeed(kmh: 2.3), [0x02, 0xE6, 0x00]),
            (.setTargetSpeed(kmh: 4), [0x02, 0x90, 0x01]),
        ]
    )
    func encodesCommand(command: ControlPointCommand, expected: [UInt8]) {
        #expect(command.bytes == expected)
    }

    @Test func decodesSuccess() throws {
        let response = try ControlPointResponse(decoding: [0x80, 0x00, 0x01])
        #expect(response.requestOpCode == 0x00)
        #expect(response.result == .success)
        #expect(response.description == "Request Control → succès")
    }

    @Test func decodesRefusal() throws {
        let response = try ControlPointResponse(decoding: [0x80, 0x02, 0x05])
        #expect(response.result == .controlNotPermitted)
        #expect(response.description == "Set Target Speed → contrôle non autorisé")
    }

    @Test func keepsUnknownResultCode() throws {
        let response = try ControlPointResponse(decoding: [0x80, 0x07, 0x09])
        #expect(response.result == nil)
        #expect(response.rawResult == 0x09)
    }

    @Test func rejectsFrameWithoutResponseCode() {
        #expect(throws: FTMSError.self) {
            try ControlPointResponse(decoding: [0x07, 0x01, 0x01])
        }
    }

    @Test func rejectsTruncatedResponse() {
        #expect(throws: FTMSError.self) {
            try ControlPointResponse(decoding: [0x80, 0x07])
        }
    }
}

struct MachineStatusTests {
    @Test(
        arguments: [
            ([UInt8]([0x02, 0x01]), MachineStatus.stoppedByUser),
            ([0x02, 0x02], .pausedByUser),
            ([0x04], .startedOrResumedByUser),
            ([0x03], .stoppedBySafetyKey),
            ([0x05, 0x2C, 0x01], .targetSpeedChanged(kmh: 3)),
            ([0x06, 0xF6, 0xFF], .targetInclinationChanged(percent: -1)),
            ([0xFF], .controlPermissionLost),
            ([0x14, 0x01], .other(opCode: 0x14, parameters: [0x01])),
        ]
    )
    func decodesStatus(frame: [UInt8], expected: MachineStatus) throws {
        #expect(try MachineStatus(decoding: frame) == expected)
    }

    @Test func pauseAndStartResetTargetSpeed() {
        #expect(MachineStatus.pausedByUser.resetsTargetSpeed)
        #expect(MachineStatus.startedOrResumedByUser.resetsTargetSpeed)
        #expect(!MachineStatus.targetSpeedChanged(kmh: 3).resetsTargetSpeed)
    }

    @Test func decodesTrainingStatus() throws {
        #expect(try TrainingStatus(decoding: [0x01, 0x0D]).description == "mode manuel")
        #expect(try TrainingStatus(decoding: [0x01, 0x0E]).description == "avant séance")
    }
}

struct MachineCapabilitiesTests {
    @Test func decodesRealFeatures() throws {
        let features = try MachineFeatures(decoding: try bytes("c4 56 00 00 0f 00 00 00"))
        #expect(features.supportsTargetSpeed)
        #expect(!features.measurements.contains("inclinaison"))
        #expect(features.measurements.contains("temps écoulé"))
        #expect(
            features.targetSettings == [
                "vitesse cible", "inclinaison cible", "résistance cible", "puissance cible",
            ]
        )
    }

    @Test func decodesRealSpeedRange() throws {
        let range = try SpeedRange(decoding: try bytes("64 00 b0 04 0a 00"))
        #expect(range == SpeedRange(minimumKmh: 1, maximumKmh: 12, incrementKmh: 0.1))
    }

    @Test func rejectsInconsistentSpeedRange() {
        #expect(throws: FTMSError.self) {
            try SpeedRange(decoding: [0xB0, 0x04, 0x64, 0x00, 0x0A, 0x00])
        }
    }
}
