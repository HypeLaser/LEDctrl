import Foundation

// LOCKED — Pages mode (auto-paginate, no In/Out effects).
// Mode 'b' auto-typeset. Long content split across pages by sign firmware.
// Rows joined by plain 0x0d. Caller must use renderMode = .stack.
//
// Do not edit without explicit approval. Working behaviour confirmed.
func renderFittedBytes(rows: [String], defaultFont: SigmaFont) -> Data {
    var rendered = Data()
    for (rowIndex, rowText) in rows.enumerated() {
        if rowIndex > 0 {
            rendered.append(0x0d)
        }
        var cleanedRow = stripTrailingMarkupTokens(rowText)
        if rowIndex == 0 {
            cleanedRow = stripLeadingColorToken(cleanedRow)
        }
        cleanedRow = stripLeadingFontToken(cleanedRow)
        rendered.append(renderMessageBytes(cleanedRow))
    }
    return rendered
}
