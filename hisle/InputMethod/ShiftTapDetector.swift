import Cocoa

struct ShiftTapDetector {
    private var pendingShift: PhysicalShift?
    private var pressedShifts = Set<PhysicalShift>()
    private var isCanceled = false

    mutating func handleFlagsChanged(
        keyCode: UInt16,
        modifiers flags: NSEvent.ModifierFlags
    ) -> HisleInputMode? {
        let meaningfulModifiers = flags.subtracting(.capsLock)
        let shift = PhysicalShift(keyCode: keyCode)

        guard let shift else {
            cancelIfGestureIsActive(resetWhenModifiersAreReleased: meaningfulModifiers.isEmpty)
            return nil
        }

        if isShiftKeyDown(shift, modifiers: meaningfulModifiers) {
            handleShiftDown(shift)
            return nil
        }

        return handleShiftUp(shift, remainingModifiers: meaningfulModifiers)
    }

    mutating func cancelForKeyInput() {
        guard pendingShift != nil else {
            return
        }
        isCanceled = true
    }

    private mutating func isShiftKeyDown(
        _ shift: PhysicalShift,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        if pressedShifts.contains(shift) {
            pressedShifts.remove(shift)
            return false
        }

        guard modifiers.contains(.shift) else {
            return false
        }

        pressedShifts.insert(shift)
        return true
    }

    private mutating func handleShiftDown(_ shift: PhysicalShift) {
        guard let current = pendingShift else {
            pendingShift = shift
            isCanceled = false
            return
        }

        if current != shift {
            isCanceled = true
        }
    }

    private mutating func handleShiftUp(
        _ shift: PhysicalShift,
        remainingModifiers: NSEvent.ModifierFlags
    ) -> HisleInputMode? {
        defer {
            if !remainingModifiers.contains(.shift) {
                reset()
            }
        }

        guard pendingShift == shift, !isCanceled, remainingModifiers.isEmpty else {
            return nil
        }

        return shift.selectedInputMode
    }

    private mutating func cancelIfGestureIsActive(resetWhenModifiersAreReleased shouldReset: Bool) {
        guard pendingShift != nil else {
            return
        }

        isCanceled = true

        if shouldReset {
            reset()
        }
    }

    private mutating func reset() {
        pendingShift = nil
        pressedShifts.removeAll()
        isCanceled = false
    }
}

private enum PhysicalShift: Hashable {
    case left
    case right

    init?(keyCode: UInt16) {
        switch keyCode {
        case KeyCode.leftShift:
            self = .left
        case KeyCode.rightShift:
            self = .right
        default:
            return nil
        }
    }

    var selectedInputMode: HisleInputMode {
        switch self {
        case .left:
            return .roman
        case .right:
            return .hangul
        }
    }
}
