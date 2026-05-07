import Foundation

// Effects mode (vendor M1 wire format).
//
// Each row is its own page. Rows separated by plain 0x0d, mode 'a'
// auto-typeset OFF. The default In/Out codes from SigmaTextOptions apply
// to every row by default. When `perRowEffects` provides an override for
// row N, an inline pair of effect-change bytes is emitted before that row:
//   0x0a 0x49 <inCode>   set In effect for next page
//   0x0a 0x4f <outCode>  set Out effect for next page
//
// `perRowEffects` may have fewer entries than rows; missing or nil entries
// fall back to the global In/Out from the NMG header.
func renderSlidesBytes(
    rows: [String],
    defaultFont: SigmaFont,
    perRowEffects: [SigmaTextOptions.RowEffect?]? = nil
) -> Data {
    var rendered = Data()
    for (rowIndex, rowText) in rows.enumerated() {
        if rowIndex > 0 {
            rendered.append(0x0d)
        }

        if let overrides = perRowEffects,
           rowIndex < overrides.count,
           let eff = overrides[rowIndex] {
            if let inCode = eff.inEffectCode {
                rendered.append(contentsOf: [0x0a, 0x49, inCode])
            }
            if let outCode = eff.outEffectCode {
                rendered.append(contentsOf: [0x0a, 0x4f, outCode])
            }
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
