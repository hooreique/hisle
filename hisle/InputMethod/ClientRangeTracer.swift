#if DEBUG
import Foundation
import InputMethodKit
import os

struct ClientRangeTracer {
    let logger: Logger

    var isEnabled: Bool {
        Self.debugFlagIsEnabled(
            environmentKey: "HISLE_TRACE_CLIENT_RANGES",
            defaultsKey: "traceClientRanges"
        )
    }

    func logInconsistentMarkedRangeIfNeeded(client: IMKTextInput?, markedText: MarkedTextState) {
        logInconsistentMarkedRangeIfNeeded(
            client: client,
            markedText: markedText,
            isConsistent: MarkedTextRangePolicy.isSelectionRange
        )
    }

    func logDefaultInconsistentMarkedRangeIfNeeded(client: IMKTextInput?, markedText: MarkedTextState) {
        logInconsistentMarkedRangeIfNeeded(
            client: client,
            markedText: markedText,
            isConsistent: DefaultMarkedTextRangePolicy.isSelectionRange
        )
    }

    private func logInconsistentMarkedRangeIfNeeded(
        client: IMKTextInput?,
        markedText: MarkedTextState,
        isConsistent: (NSRange, NSRange) -> Bool
    ) {
        guard isEnabled, markedText.isActive, let client else {
            return
        }

        let selectedRange = client.selectedRange()
        let markedRange = client.markedRange()
        guard selectedRange.location != NSNotFound else {
            return
        }

        if markedRange.location != NSNotFound,
           markedRange.length > 0,
           isConsistent(selectedRange, markedRange) {
            return
        }

        let message = "inconsistent ranges selected=\(NSStringFromRange(selectedRange)) " +
            "marked=\(NSStringFromRange(markedRange))"
        logger.debug("\(message, privacy: .public)")
    }

    func traceClientRanges(_ stage: String, client: IMKTextInput?, markedText: MarkedTextState) {
        guard isEnabled else {
            return
        }

        guard let client else {
            logger.debug("client-range stage=\(stage, privacy: .public) missing-client")
            return
        }

        traceClientRanges(stage, client: client, markedText: markedText)
    }

    func traceClientRanges(_ stage: String, client: IMKTextInput, markedText: MarkedTextState) {
        guard isEnabled else {
            return
        }

        let message = [
            "client-range stage=\(stage)",
            "selected=\(NSStringFromRange(client.selectedRange()))",
            "marked=\(NSStringFromRange(client.markedRange()))",
            "hasMarkedText=\(markedText.isActive)",
            "currentMarkedLength=\(markedText.utf16Count)"
        ].joined(separator: " ")
        logger.debug("\(message, privacy: .public)")
    }

    func traceReplacementRange(
        _ decision: MarkedTextReplacementDecision,
        markedText: MarkedTextState
    ) {
        guard isEnabled else {
            return
        }

        let message = [
            "client-range replacement=\(NSStringFromRange(decision.replacementRange))",
            "reason=\(decision.reason.rawValue)",
            "selected=\(NSStringFromRange(decision.selectedRange))",
            "marked=\(NSStringFromRange(decision.markedRange))",
            "hasMarkedText=\(markedText.isActive)",
            "currentMarkedLength=\(markedText.utf16Count)"
        ].joined(separator: " ")
        logger.debug("\(message, privacy: .public)")
    }

    func traceDefaultReplacementRange(
        _ decision: DefaultMarkedTextReplacementDecision,
        markedText: MarkedTextState
    ) {
        guard isEnabled else {
            return
        }

        let message = [
            "client-range replacement=\(NSStringFromRange(decision.replacementRange))",
            "reason=\(decision.reason.rawValue)",
            "selected=\(NSStringFromRange(decision.selectedRange))",
            "marked=\(NSStringFromRange(decision.markedRange))",
            "hasMarkedText=\(markedText.isActive)",
            "currentMarkedLength=\(markedText.utf16Count)"
        ].joined(separator: " ")
        logger.debug("\(message, privacy: .public)")
    }

    func traceUpdateCompositionReplacementRange(
        _ replacementRange: NSRange,
        reason: MarkedTextRangeReason,
        client: IMKTextInput?,
        markedText: MarkedTextState
    ) {
        guard isEnabled else {
            return
        }

        guard let client else {
            let message = "client-range update-composition " +
                "replacement=\(NSStringFromRange(replacementRange)) reason=\(reason.rawValue) missing-client"
            logger.debug("\(message, privacy: .public)")
            return
        }

        let message = [
            "client-range update-composition replacement=\(NSStringFromRange(replacementRange))",
            "reason=\(reason.rawValue)",
            "selected=\(NSStringFromRange(client.selectedRange()))",
            "marked=\(NSStringFromRange(client.markedRange()))",
            "hasMarkedText=\(markedText.isActive)",
            "currentMarkedLength=\(markedText.utf16Count)"
        ].joined(separator: " ")
        logger.debug("\(message, privacy: .public)")
    }

    func traceDefaultUpdateCompositionReplacementRange(
        _ replacementRange: NSRange,
        reason: DefaultMarkedTextRangeReason,
        client: IMKTextInput?,
        markedText: MarkedTextState
    ) {
        guard isEnabled else {
            return
        }

        guard let client else {
            let message = "client-range update-composition " +
                "replacement=\(NSStringFromRange(replacementRange)) reason=\(reason.rawValue) missing-client"
            logger.debug("\(message, privacy: .public)")
            return
        }

        let message = [
            "client-range update-composition replacement=\(NSStringFromRange(replacementRange))",
            "reason=\(reason.rawValue)",
            "selected=\(NSStringFromRange(client.selectedRange()))",
            "marked=\(NSStringFromRange(client.markedRange()))",
            "hasMarkedText=\(markedText.isActive)",
            "currentMarkedLength=\(markedText.utf16Count)"
        ].joined(separator: " ")
        logger.debug("\(message, privacy: .public)")
    }

    private static func debugFlagIsEnabled(environmentKey: String, defaultsKey: String) -> Bool {
        if let environmentValue = ProcessInfo.processInfo.environment[environmentKey] {
            let normalizedValue = environmentValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["1", "true", "yes", "on"].contains(normalizedValue)
        }

        if UserDefaults.standard.bool(forKey: defaultsKey) {
            return true
        }

        return UserDefaults(suiteName: HisleInputModeState.suiteName)?.bool(forKey: defaultsKey) == true
    }
}
#endif
