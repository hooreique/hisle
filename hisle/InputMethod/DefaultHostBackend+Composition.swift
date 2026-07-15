import Foundation
import HisleCore
import InputMethodKit
import os

extension DefaultHostBackend {
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

        let plan = DefaultHostApplyPlan.make(
            committedText: output.committedText,
            markedText: output.markedText,
            wasMarkedTextActive: markedText.isActive
        )

        if let committedText = plan.committedText {
            let replacementRange = insertCommittedText(
                committedText,
                client: client,
                traceAction: "commit"
            )

            if plan.needsMarkedTextContinuation {
                pendingMarkedTextReplacementRange = DefaultMarkedTextRangePolicy.continuationRange(
                    afterReplacing: replacementRange,
                    withCommittedText: committedText,
                    selectedRange: client.selectedRange()
                )
            }
        }

        switch plan.markedTextAction {
        case .update(let text):
            updateMarkedText(text, client: client)
        case .clear:
            clearMarkedText(client: client)
        case .none:
            break
        }

        return true
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
        markedText.replace(with: text)
#if DEBUG
        ClientRangeTracer(logger: logger).traceClientRanges(
            "before-update-composition markedLength=\(text.utf16.count)",
            client: client,
            markedText: markedText
        )
#endif
        updateComposition()
#if DEBUG
        ClientRangeTracer(logger: logger).traceClientRanges(
            "after-update-composition markedLength=\(text.utf16.count)",
            client: client,
            markedText: markedText
        )
#endif
    }

    private func clearMarkedText(client: IMKTextInput) {
        markedText.clear()
#if DEBUG
        ClientRangeTracer(logger: logger).traceClientRanges(
            "before-clear-composition",
            client: client,
            markedText: markedText
        )
#endif
        updateComposition()
#if DEBUG
        ClientRangeTracer(logger: logger).traceClientRanges(
            "after-clear-composition",
            client: client,
            markedText: markedText
        )
#endif
    }

    private func replacementRange(for client: IMKTextInput) -> NSRange {
        let decision = DefaultMarkedTextRangePolicy.replacementDecision(
            hasMarkedText: markedText.isActive,
            selectedRange: client.selectedRange(),
            markedRange: client.markedRange()
        )
#if DEBUG
        ClientRangeTracer(logger: logger).traceDefaultReplacementRange(
            decision,
            markedText: markedText
        )
#endif
        return decision.replacementRange
    }
}
