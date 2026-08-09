import AppKit
import SwiftUI

/// The output of something that is running.
///
/// It exists because both log boxes in the app were one `Text` holding the
/// whole log, and that froze the window. `xcodebuild archive` prints several
/// hundred lines a second, and every one of them did this:
///
/// 1. The line landed in an observed array, so SwiftUI invalidated the view.
/// 2. The redraw joined two thousand strings into one, which allocates the
///    whole log again.
/// 3. `Text` laid out that string. A `Text` is not virtualized, so all two
///    thousand lines were measured and typeset to draw the fifteen the box is
///    tall, and `.textSelection` made TextKit do it properly.
///
/// Several hundred times a second, on the main thread. The window stopped
/// answering, which is exactly what a developer sees after they press Build
/// Archive and then Show log.
///
/// A `LazyVStack` lays out the rows it draws and no others, so the cost is the
/// height of the box rather than the length of the log. The tail is what a
/// running build is read for, and the whole thing is one button away.
///
/// `// ponytail: a lazy stack and a tail. No text view, no attributed string,
/// // no windowing of my own. The framework already virtualizes a lazy stack.`
struct LogView: View {
    let lines: [String]
    var height: CGFloat = 220
    /// What the box draws. The rest of the log stays in memory and reaches the
    /// pasteboard, so nothing here loses a line.
    var tail = 400

    /// The rows, oldest of the visible ones first, with the position each one
    /// holds in the whole log. The index is the identity: a build prints the
    /// same line many times, and `id: \.self` on repeated strings gives
    /// SwiftUI duplicate identities to reconcile.
    private var rows: [(offset: Int, element: String)] {
        Array(lines.enumerated().suffix(tail))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            box
            // The box draws the tail and says so, so the offer has to be
            // keepable. This hands over every line the run still holds.
            Button("Copy the log") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(lines.joined(separator: "\n"),
                                               forType: .string)
            }
            .controlSize(.small)
            .disabled(lines.isEmpty)
        }
    }

    private var box: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if lines.count > tail {
                    Text("\(lines.count - tail) earlier lines. Copy the log to read them.")
                        .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                        .padding(.bottom, 4)
                }
                ForEach(rows, id: \.offset) { row in
                    Text(row.element)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.text2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A log is read at the end, on the first frame as much as on the
        // hundredth: a developer who presses Show log after the build wants
        // the line that ended it, not the line 400 back.
        //
        // ponytail: the anchor, not a ScrollViewReader. It holds the bottom
        // when the box opens and again every time the content grows, which is
        // the whole of what a scrollTo per flush was doing.
        .defaultScrollAnchor(.bottom)
        .frame(height: height)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 7))
    }
}
