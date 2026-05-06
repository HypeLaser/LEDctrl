# Font Notes for 80x7 LED Sign

The panel is only 80 pixels wide by 7 pixels high, so the vertical budget is the hard limit. Good defaults should be pixel fonts designed for 7 rows or fewer, with predictable spacing.

## Recommended Styles

1. **Classic 5x7**
   - Best all-round readability.
   - Use 1 blank pixel between characters, so each uppercase character costs about 6 columns.
   - Fits about 13 characters across 80 pixels with spacing.
   - Best for short fixed messages: `OPEN`, `BACK SOON`, `WEATHER 12C`.

2. **Condensed 4x7**
   - Still uses the full 7-pixel height but narrows most letters.
   - Fits about 16 characters with 1-pixel spacing.
   - Good for centered headlines and station-style labels.

3. **Tiny 3x5 / 3x6**
   - Fits about 20 characters with spacing, more if variable-width.
   - Best for dense weather data, time, temperatures, arrows, and compact status lines.
   - Less readable for arbitrary mixed-case sentences; use uppercase and avoid visually similar letters where possible.

4. **Variable-Width 5x7**
   - Same height as Classic 5x7 but narrow glyphs like `I`, `1`, punctuation, and spaces use fewer columns.
   - Better for natural-language headlines because the line length depends on actual glyph widths, not a fixed cell.

## Spacing Rules

- Use at least 1 blank column between characters for normal reading.
- For marquee text, keep 1 blank column but add a wider gap between repeated messages.
- Avoid lowercase descenders in 7 pixels unless the font is specifically drawn for them.
- Prefer uppercase for public/headline display because 5x7 uppercase is substantially cleaner than lowercase at this height.
- For punctuation-heavy feeds, normalize smart punctuation before rendering: curly quotes, ellipses, en dashes, non-breaking spaces, and semicolons can confuse the current Sigma text format.

## App Direction

The app should eventually offer:

- `Readable 5x7`: default, centered/fitted short messages.
- `Condensed 4x7`: more characters without scrolling.
- `Tiny 3x5`: data-dense weather/status mode.
- `Variable 5x7`: smarter headline rendering.
- `Icon Font`: arrows, weather symbols, dots, chevrons, separators.

The current hardware text path exposes Sigma's built-in fonts, but our bitmap path can draw custom fonts once the NMG bitmap upload format is stable.

## Vendor Font Findings

- The Sigma software ships actual bitmap font files in `/Users/alexscott/Projects/MessageMaker/sigma3000_extracted/FONT`.
- `FontList.fst` names `Normal5.fnt`, `Normal7.fnt`, `Normal11.fnt`, `Normal14.fnt`, `Normal15.fnt`, `Normal16.fnt`, plus `SonTi16.FNT` and `Russian16.fnt`.
- `PCFontList.fst` also names `bold5.fnt`, `bold14.fnt`, `bold15.fnt`, and `bold16.fnt`.
- For the 80x7 sign, only the `5`, `7`, and custom bitmap/PMG paths are physically useful. Larger vendor fonts either crop or become irrelevant unless used to render a graphic before scaling/cropping.
- Inline `1A 30` / `{font5}` is accepted by the sign, but the built-in text engine baseline-aligns it to the bottom LEDs. The Sigma manual says the editor has a vertical-centre command; this byte is not mapped yet and needs a one-change capture.

## External Font Leads

- MatrixSans is a 5x7 dot-matrix font family and is a useful visual reference for the classic LCD/LED look.
- 5x7 MT Pixel is a small 5x7 pixel font worth comparing for punctuation and numerals.
- The X11 `misc-fixed` family includes public-domain bitmap fonts; its 5x7 style is useful as a baseline alphabet.
- For LEDctrl, the most robust plan is not to rely on TTF rendering. Store tiny bitmap alphabets directly as glyph tables, then render them into the 80x7 pixel buffer. That gives us centred 5-high words, 4x7 condensed text, chevrons, weather symbols, and whole-frame image/marquee animation without depending on the sign's own text font baseline.
