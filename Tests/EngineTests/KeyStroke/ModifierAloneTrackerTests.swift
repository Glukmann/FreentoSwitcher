import Testing
@testable import Engine

struct ModifierAloneTrackerTests {
    @Test func singleOptionDownUpFires() {
        var t = ModifierAloneTracker()
        #expect(t.handle(keycode: 0x3A, phase: .down, isTrackedModifier: isOption) == false)
        #expect(t.handle(keycode: 0x3A, phase: .up, isTrackedModifier: isOption) == true)
    }

    @Test func otherKeyBetweenPressAndReleaseCancels() {
        var t = ModifierAloneTracker()
        #expect(t.handle(keycode: 0x3A, phase: .down, isTrackedModifier: isOption) == false)
        #expect(t.handle(keycode: 0x05, phase: .down, isTrackedModifier: isOption) == false)
        #expect(t.handle(keycode: 0x3A, phase: .up, isTrackedModifier: isOption) == false)
    }

    @Test func secondModifierHeldUntilBothReleased() {
        var t = ModifierAloneTracker()
        #expect(t.handle(keycode: 0x3A, phase: .down, isTrackedModifier: isOption) == false)
        #expect(t.handle(keycode: 0x3D, phase: .down, isTrackedModifier: isOption) == false)
        #expect(t.handle(keycode: 0x3A, phase: .up, isTrackedModifier: isOption) == false) // правый ещё зажат
        #expect(t.handle(keycode: 0x3D, phase: .up, isTrackedModifier: isOption) == true)  // оба отпущены
    }

    @Test func repeatedCyclesFireEachTime() {
        var t = ModifierAloneTracker()
        #expect(t.handle(keycode: 0x3A, phase: .down, isTrackedModifier: isOption) == false)
        #expect(t.handle(keycode: 0x3A, phase: .up, isTrackedModifier: isOption) == true)
        #expect(t.handle(keycode: 0x3A, phase: .down, isTrackedModifier: isOption) == false)
        #expect(t.handle(keycode: 0x3A, phase: .up, isTrackedModifier: isOption) == true)
    }

    @Test func autoRepeatKeyDownDoesNotCancel() {
        var t = ModifierAloneTracker()
        #expect(t.handle(keycode: 0x3A, phase: .down, isTrackedModifier: isOption) == false)
        #expect(t.handle(keycode: 0x3A, phase: .down, isTrackedModifier: isOption) == false) // автоповтор
        #expect(t.handle(keycode: 0x3A, phase: .up, isTrackedModifier: isOption) == true)
    }

    @Test func untrackedKeysPassThroughWithoutPollutingState() {
        var t = ModifierAloneTracker()
        #expect(t.handle(keycode: 0x05, phase: .down, isTrackedModifier: isOption) == false)
        #expect(t.handle(keycode: 0x05, phase: .up, isTrackedModifier: isOption) == false)
        #expect(t.handle(keycode: 0x3A, phase: .down, isTrackedModifier: isOption) == false)
        #expect(t.handle(keycode: 0x3A, phase: .up, isTrackedModifier: isOption) == true)
    }

    @Test func otherKeyReleaseDoesNotResetAloneFlag() {
        var t = ModifierAloneTracker()
        #expect(t.handle(keycode: 0x3A, phase: .down, isTrackedModifier: isOption) == false)
        #expect(t.handle(keycode: 0x05, phase: .down, isTrackedModifier: isOption) == false)
        #expect(t.handle(keycode: 0x05, phase: .up, isTrackedModifier: isOption) == false)
        #expect(t.handle(keycode: 0x3A, phase: .up, isTrackedModifier: isOption) == false) // сбросил только keyDown 0x05
    }
}

private func isOption(_ keycode: UInt16) -> Bool {
    keycode == 0x3A || keycode == 0x3D
}
