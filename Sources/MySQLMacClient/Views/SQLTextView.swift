import SwiftUI
import AppKit

/// A plain `TextEditor` can't color individual words, so the SQL panel uses
/// this `NSTextView` wrapper instead — reserved-word highlighting is
/// reapplied to the whole buffer on every edit. Queries are short enough
/// that re-highlighting from scratch each keystroke is cheap; this isn't
/// meant to scale to editing large scripts.
struct SQLTextView: NSViewRepresentable {
    @Binding var text: String
    /// One-shot signal: when set, its text is inserted at the *current*
    /// cursor position (double-clicking a table/column in the sidebar sets
    /// this) and the binding is cleared back to `nil` right after.
    @Binding var pendingInsertion: String?

    static let keywords: Set<String> = [
        "select", "from", "where", "insert", "into", "values", "update", "set",
        "delete", "create", "table", "alter", "drop", "index", "primary", "key",
        "foreign", "references", "join", "inner", "left", "right", "outer", "cross", "on",
        "group", "by", "order", "having", "limit", "offset", "as", "and", "or",
        "not", "null", "is", "in", "like", "between", "distinct", "union", "all",
        "exists", "case", "when", "then", "else", "end", "asc", "desc", "default",
        "auto_increment", "unique", "constraint", "cascade", "view", "trigger",
        "procedure", "function", "database", "schema", "show", "describe", "explain",
        "truncate", "replace", "use", "column", "add", "modify", "change", "if",
    ]

    static let keywordColor = NSColor.systemBlue
    static let stringLiteralColor = NSColor.systemGreen
    static let commentColor = NSColor.systemGray

    private static let keywordRegex = try! NSRegularExpression(
        pattern: #"\b(\#(keywords.joined(separator: "|")))\b"#,
        options: [.caseInsensitive]
    )
    private static let stringLiteralRegex = try! NSRegularExpression(pattern: #"'[^']*'|"[^"]*""#)
    private static let commentRegex = try! NSRegularExpression(pattern: #"--[^\n]*"#)

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = text
        context.coordinator.highlight(textView)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        context.coordinator.textView = textView
        return scrollView
    }

    /// The `pendingInsertion != nil` branch used to clear the binding
    /// *asynchronously* after also manually re-syncing `text`/highlighting.
    /// That manual `text = textView.string` assignment made SwiftUI call
    /// `updateNSView` again immediately — before the async clear had run —
    /// so this branch re-entered and inserted the same text again, and
    /// again, in a tight synchronous loop with no yield back to the run
    /// loop. The text ballooned every cycle, `highlight()` re-scanned the
    /// ever-growing string with regex on every cycle, and the whole
    /// machine froze hard enough to force a restart.
    ///
    /// Fix: clear `pendingInsertion` *synchronously, before* triggering
    /// anything that could cascade back into this method, and don't
    /// manually touch `text`/`highlight()` at all here — `insertText(_:)`
    /// goes through the normal AppKit editing pipeline and already fires
    /// `textDidChange` below, which does that syncing exactly like real
    /// typing would. By the time any re-entrant call arrives,
    /// `pendingInsertion` is already `nil`.
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if let insertion = pendingInsertion {
            pendingInsertion = nil
            textView.window?.makeFirstResponder(textView)
            textView.insertText(insertion, replacementRange: textView.selectedRange())
            return
        }

        guard textView.string != text else { return }
        textView.string = text
        context.coordinator.highlight(textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            uppercaseKeywords(in: textView)
            text.wrappedValue = textView.string
            highlight(textView)
        }

        /// Rewrites any reserved word to its uppercase form in place. Runs
        /// before `highlight()`'s coloring pass so the two always agree —
        /// "the blue ones are always uppercase" is the point, not just a
        /// visual effect. Uppercasing ASCII keywords never changes their
        /// character count, so the caret position is restorable verbatim
        /// afterward instead of jumping around while typing.
        private func uppercaseKeywords(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let nsString = storage.string as NSString
            let fullRange = NSRange(location: 0, length: nsString.length)
            let savedSelection = textView.selectedRanges

            var replacements: [(NSRange, String)] = []
            for match in SQLTextView.keywordRegex.matches(in: storage.string, range: fullRange) {
                let word = nsString.substring(with: match.range)
                let upper = word.uppercased()
                if word != upper {
                    replacements.append((match.range, upper))
                }
            }
            guard !replacements.isEmpty else { return }

            storage.beginEditing()
            for (range, replacement) in replacements.reversed() {
                storage.replaceCharacters(in: range, with: replacement)
            }
            storage.endEditing()
            textView.selectedRanges = savedSelection
        }

        func highlight(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let string = storage.string
            let fullRange = NSRange(location: 0, length: (string as NSString).length)

            storage.beginEditing()
            storage.setAttributes(
                [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.labelColor],
                range: fullRange
            )
            for match in SQLTextView.keywordRegex.matches(in: string, range: fullRange) {
                storage.addAttributes(
                    [.foregroundColor: SQLTextView.keywordColor, .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)],
                    range: match.range
                )
            }
            for match in SQLTextView.stringLiteralRegex.matches(in: string, range: fullRange) {
                storage.addAttribute(.foregroundColor, value: SQLTextView.stringLiteralColor, range: match.range)
            }
            for match in SQLTextView.commentRegex.matches(in: string, range: fullRange) {
                storage.addAttribute(.foregroundColor, value: SQLTextView.commentColor, range: match.range)
            }
            storage.endEditing()
        }
    }
}
