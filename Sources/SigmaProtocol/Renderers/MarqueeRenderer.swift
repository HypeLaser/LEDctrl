import Foundation

// LOCKED — Marquee mode (continuous scroll with full-screen-width gaps).
// Mode 'a' auto-typeset OFF. All rows joined into one scroll line, separated
// by a 20-space spacer (~ full 80px display width in normal7) so row 1 fully
// exits before row 2 enters. Total content padded to >16 chars to force the
// firmware into scroll mode even on short inputs.
//
// Do not edit without explicit approval. Behaviour confirmed by user.
private let marqueeRowSpacer = String(repeating: " ", count: 20)
private let marqueeMinTotalChars = 22

func renderMarqueeBytes(rows: [String], defaultFont: SigmaFont) -> Data {
    var cleaned: [String] = []
    for (rowIndex, rowText) in rows.enumerated() {
        var row = stripTrailingMarkupTokens(rowText)
        if rowIndex == 0 {
            row = stripLeadingColorToken(row)
        }
        row = stripLeadingFontToken(row)
        cleaned.append(row)
    }

    var joined = cleaned.joined(separator: marqueeRowSpacer)

    // Pad short content so total visible width exceeds the display, forcing
    // the firmware to scroll instead of static-display the line.
    let visibleWidth = messageDisplayWidth(joined)
    if visibleWidth < marqueeMinTotalChars {
        joined.append(String(repeating: " ", count: marqueeMinTotalChars - visibleWidth))
    }

    var rendered = Data()
    rendered.append(renderMessageBytes(joined))
    return rendered
}
