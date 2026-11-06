import Testing

@testable import FTMSKit

struct SpeedPolicyTests {
    private let policy = SpeedPolicy(
        range: SpeedRange(minimumKmh: 1, maximumKmh: 12, incrementKmh: 0.1),
        ceilingKmh: 4,
    )

    @Test func capsAtCeiling() {
        #expect(policy.maximumKmh == 4)
        #expect(policy.clamped(6) == 4)
        #expect(policy.stepped(from: 4, direction: 1) == 4)
    }

    @Test func neverGoesBelowMachineMinimum() {
        #expect(policy.clamped(0) == 1)
        #expect(policy.stepped(from: 1, direction: -1) == 1)
    }

    @Test func roundsToMachineIncrement() {
        #expect(policy.clamped(2.34) == 2.3)
        #expect(policy.clamped(2.36) == 2.4)
    }

    @Test func buttonsMoveByMachineIncrement() {
        #expect(policy.buttonStepKmh == 0.1)
        #expect(policy.stepped(from: 2, direction: 1) == 2.1)
        #expect(policy.stepped(from: 2.1, direction: -1) == 2)
        #expect(policy.stepped(from: 3.9, direction: 1) == 4)
    }

    @Test func preferredStepWidensButtons() {
        let coarse = SpeedPolicy(range: policy.range, ceilingKmh: 4, preferredStepKmh: 0.5)
        #expect(coarse.buttonStepKmh == 0.5)
        #expect(coarse.stepped(from: 2, direction: 1) == 2.5)
        #expect(coarse.stepped(from: 3.8, direction: 1) == 4)
    }

    @Test func preferredStepNeverFinerThanMachine() {
        let tooFine = SpeedPolicy(range: policy.range, ceilingKmh: 4, preferredStepKmh: 0.01)
        #expect(tooFine.buttonStepKmh == 0.1)
    }

    @Test func machineMaximumWinsOverHigherCeiling() {
        let permissive = SpeedPolicy(range: policy.range, ceilingKmh: 20)
        #expect(permissive.maximumKmh == 12)
    }

    @Test func coarseMachineIncrementSetsButtonStep() {
        let coarse = SpeedPolicy(
            range: SpeedRange(minimumKmh: 1, maximumKmh: 12, incrementKmh: 1),
            ceilingKmh: 6,
        )
        #expect(coarse.buttonStepKmh == 1)
        #expect(coarse.clamped(2.4) == 2)
    }
}
