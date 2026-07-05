import Foundation
import HisleCore
import InputMethodKit
import os

extension InputController {
    func process(_ input: ColeSebeolInput, client sender: Any?) -> Bool {
        let output = hangulEngine.process(input)
        guard apply(output, to: sender) else {
            return false
        }
        return output.forwardedActions.isEmpty
    }

    func flushBeforeForwarding(to sender: Any?) {
        guard markedText.isActive else {
            return
        }
        _ = apply(hangulEngine.process(.flush), to: sender)
    }

    func commitRomanText(_ text: String, client sender: Any?) -> Bool {
        flushBeforeForwarding(to: sender)
        return commitText(text, client: sender)
    }

    func apply(_ output: ColeSebeolOutput, to sender: Any?) -> Bool {
        guard let client = textClient(from: sender) else {
            logger.error("missing IMKTextInput client")
            return false
        }

        if !output.committedText.isEmpty {
            let replacementRange = insertCommittedText(output.committedText, client: client, traceAction: "commit")

            if !output.markedText.isEmpty {
                pendingMarkedTextReplacement = markedTextRangeTracker.replacementForMarkedTextUpdate(
                    wasMarkedTextActive: false
                ) ?? MarkedTextRangePolicy.continuationReplacement(
                    afterReplacing: replacementRange,
                    withCommittedText: output.committedText
                )
            }
        }

        if !output.markedText.isEmpty {
            updateMarkedText(output.markedText, client: client)
        } else if markedText.isActive {
            clearMarkedText(client: client)
        }

        return true
    }

    func textClient(from sender: Any?) -> IMKTextInput? {
        if let client = sender as? IMKTextInput {
            return client
        }
        return client()
    }

    private func commitText(_ text: String, client sender: Any?) -> Bool {
        guard let client = textClient(from: sender) else {
            logger.error("missing IMKTextInput client")
            return false
        }

        _ = insertCommittedText(text, client: client)
        return true
    }

    private func insertCommittedText(
        _ text: String,
        client: IMKTextInput,
        traceAction: String = "insert"
    ) -> NSRange {
        let wasMarkedTextActive = markedText.isActive
        let replacementRange = replacementRange(for: client)
#if DEBUG
        ClientRangeTracer(logger: logger).traceClientRanges(
            "before-\(traceAction) committedLength=\(text.utf16.count) " +
                "replacement=\(NSStringFromRange(replacementRange))",
            client: client,
            markedText: markedText
        )
#endif
        client.insertText(text, replacementRange: replacementRange)
        markedTextRangeTracker.recordCommittedText(
            replacementRange: replacementRange,
            committedLength: text.utf16.count,
            wasMarkedTextActive: wasMarkedTextActive,
            client: client
        )
        markedText.clear()
#if DEBUG
        ClientRangeTracer(logger: logger).traceClientRanges(
            "after-\(traceAction) committedLength=\(text.utf16.count)",
            client: client,
            markedText: markedText
        )
#endif
        return replacementRange
    }

    private func updateMarkedText(_ text: String, client: IMKTextInput) {
        let wasMarkedTextActive = markedText.isActive
        if pendingMarkedTextReplacement == nil {
            pendingMarkedTextReplacement = markedTextRangeTracker.replacementForMarkedTextUpdate(
                wasMarkedTextActive: wasMarkedTextActive
            )
        }

        markedText.replace(with: text)
#if DEBUG
        ClientRangeTracer(logger: logger).traceClientRanges(
            "before-update-composition markedLength=\(text.utf16.count)",
            client: client,
            markedText: markedText
        )
#endif
        updateComposition()
        let replacementRange = lastUpdateCompositionReplacementRange
            ?? MarkedTextRangePolicy.currentSelectionReplacementRange
        markedTextRangeTracker.recordMarkedTextUpdate(
            replacementRange: replacementRange,
            markedLength: text.utf16.count,
            client: client
        )
#if DEBUG
        ClientRangeTracer(logger: logger).traceClientRanges(
            "after-update-composition markedLength=\(text.utf16.count)",
            client: client,
            markedText: markedText
        )
#endif
    }

    private func clearMarkedText(client: IMKTextInput) {
        if pendingMarkedTextReplacement == nil {
            pendingMarkedTextReplacement = markedTextRangeTracker.replacementForMarkedTextUpdate(
                wasMarkedTextActive: true
            )
        }

        markedText.clear()
#if DEBUG
        ClientRangeTracer(logger: logger).traceClientRanges(
            "before-clear-composition",
            client: client,
            markedText: markedText
        )
#endif
        updateComposition()
        markedTextRangeTracker.recordMarkedTextClear(client: client)
#if DEBUG
        ClientRangeTracer(logger: logger).traceClientRanges(
            "after-clear-composition",
            client: client,
            markedText: markedText
        )
#endif
    }

    private func replacementRange(for client: IMKTextInput) -> NSRange {
        let decision = MarkedTextRangePolicy.replacementDecision(
            hasMarkedText: markedText.isActive,
            ownedMarkedRange: markedTextRangeTracker.markedRange,
            ownedInsertionRange: markedTextRangeTracker.insertionRange,
            client: client
        )
#if DEBUG
        ClientRangeTracer(logger: logger).traceReplacementRange(decision, markedText: markedText)
#endif
        return decision.replacementRange
    }
}
