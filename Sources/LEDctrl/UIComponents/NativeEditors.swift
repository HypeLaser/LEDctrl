import Foundation
import SwiftUI
import AppKit

struct NativeMessageField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    init(text: Binding<String>, placeholder: String, onSubmit: @escaping () -> Void = {}) {
        self._text = text
        self.placeholder = placeholder
        self.onSubmit = onSubmit
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusTextField(string: text)
        field.placeholderString = placeholder
        field.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.isEditable = true
        field.isSelectable = true
        field.backgroundColor = NSColor.controlBackgroundColor
        field.drawsBackground = true
        field.focusRingType = .default
        field.refusesFirstResponder = false
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        @objc func submit() {
            onSubmit()
        }
    }

    final class FocusTextField: NSTextField {
        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }

        override func becomeFirstResponder() -> Bool {
            let didBecome = super.becomeFirstResponder()
            currentEditor()?.selectAll(nil)
            return didBecome
        }
    }
}

struct NativeRowTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onFocus: () -> Void
    let onSelectionChange: (NSRange) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = RowTextView()
        textView.string = text
        textView.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .bold)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.drawsBackground = true
        textView.backgroundColor = .controlBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 5)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.textContainer?.heightTracksTextView = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 34)
        context.coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.text = $text
        context.coordinator.onFocus = onFocus
        context.coordinator.onSelectionChange = onSelectionChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onFocus: onFocus, onSelectionChange: onSelectionChange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onFocus: () -> Void
        var onSelectionChange: (NSRange) -> Void
        weak var textView: NSTextView?

        init(text: Binding<String>, onFocus: @escaping () -> Void, onSelectionChange: @escaping (NSRange) -> Void) {
            self.text = text
            self.onFocus = onFocus
            self.onSelectionChange = onSelectionChange
        }

        func textDidBeginEditing(_ notification: Notification) {
            onFocus()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            onSelectionChange(textView.selectedRange())
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onFocus()
            onSelectionChange(textView.selectedRange())
        }
    }

    final class RowTextView: NSTextView {
        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }
    }
}

struct NativeCanvasTextEditor: NSViewRepresentable {
    @Binding var text: String
    let styleRuns: [CanvasStyleRun]
    let baseColor: AppColor
    let basePalette: AppPalette
    let showsVisibleText: Bool
    let placeholder: String
    let onSelectionChange: (NSRange) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CanvasTextView()
        let editorFont = NSFont.monospacedSystemFont(ofSize: 30, weight: .semibold)
        textView.font = editorFont
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 8, height: 4)
        textView.isRichText = true
        textView.importsGraphics = false
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        textView.typingAttributes = [
            .font: editorFont,
            .foregroundColor: showsVisibleText ? NSColor.labelColor : NSColor.clear
        ]
        textView.insertionPointColor = .white
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.45),
            .foregroundColor: NSColor.clear
        ]
        context.coordinator.textView = textView
        textView.textStorage?.setAttributedString(Self.attributedText(text: text, styleRuns: styleRuns, baseColor: baseColor, basePalette: basePalette, showsVisibleText: showsVisibleText))
        context.coordinator.renderedSignature = renderSignature

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text || context.coordinator.renderedSignature != renderSignature {
            let selected = textView.selectedRange()
            textView.textStorage?.setAttributedString(Self.attributedText(text: text, styleRuns: styleRuns, baseColor: baseColor, basePalette: basePalette, showsVisibleText: showsVisibleText))
            let textLength = (text as NSString).length
            let length = selected.location + selected.length <= textLength ? selected.length : 0
            textView.setSelectedRange(NSRange(location: min(selected.location, textLength), length: length))
            context.coordinator.renderedSignature = renderSignature
        }
        context.coordinator.text = $text
        context.coordinator.onSelectionChange = onSelectionChange
    }

    private var renderSignature: String {
        let runs = styleRuns
            .map { "\($0.location):\($0.length):\($0.token)" }
            .joined(separator: "|")
        return "\(text)#\(baseColor.rawValue)#\(basePalette.rawValue)#\(showsVisibleText)#\(runs)"
    }

    private static func attributedText(text: String, styleRuns: [CanvasStyleRun], baseColor: AppColor, basePalette: AppPalette, showsVisibleText: Bool) -> NSAttributedString {
        let textLength = (text as NSString).length
        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 30, weight: .semibold),
                .foregroundColor: showsVisibleText ? nsColor(for: basePalette, fallback: baseColor) : NSColor.clear
            ]
        )
        guard showsVisibleText else { return result }

        for run in styleRuns where run.length > 0 && run.location >= 0 && run.location < textLength {
            let length = min(run.length, textLength - run.location)
            applyToken(run.token, to: result, range: NSRange(location: run.location, length: length), fallback: baseColor)
        }
        return result
    }

    private static func applyToken(_ token: String, to text: NSMutableAttributedString, range: NSRange, fallback: AppColor) {
        switch token.lowercased() {
        case "{characters}", "{diagonal_down}", "{diagonal_up}":
            for offset in 0..<range.length {
                let colorIndex: Int
                if token.lowercased() == "{diagonal_up}" {
                    colorIndex = (range.length - offset - 1) % 3
                } else if token.lowercased() == "{diagonal_down}" {
                    colorIndex = offset % 3
                } else {
                    colorIndex = offset % 3
                }
                text.addAttributes([.foregroundColor: palettePreviewColor(colorIndex)], range: NSRange(location: range.location + offset, length: 1))
            }
        case "{bands}":
            text.addAttributes([
                .foregroundColor: NSColor.systemYellow,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: NSColor.systemGreen
            ], range: range)
        default:
            text.addAttributes([.foregroundColor: nsColor(forToken: token, fallback: fallback)], range: range)
        }
    }

    private static func palettePreviewColor(_ index: Int) -> NSColor {
        switch index % 3 {
        case 0: return .systemRed
        case 1: return .systemGreen
        default: return .systemYellow
        }
    }

    private static func nsColor(for palette: AppPalette, fallback: AppColor) -> NSColor {
        switch palette {
        case .solid: return fallback.nsColor
        case .horizontalBands: return .systemYellow
        case .characterStripes: return .systemGreen
        case .diagonalDown: return .systemOrange
        case .diagonalUp: return .systemPurple
        }
    }

    private static func nsColor(forToken token: String, fallback: AppColor) -> NSColor {
        switch token.lowercased() {
        case "{red}": return .systemRed
        case "{green}": return .systemGreen
        case "{orange}", "{yellow}": return .systemOrange
        case "{bands}": return .systemYellow
        case "{characters}": return .systemGreen
        case "{diagonal_down}": return .systemOrange
        case "{diagonal_up}": return .systemPurple
        default: return fallback.nsColor
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSelectionChange: onSelectionChange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSelectionChange: (NSRange) -> Void
        weak var textView: NSTextView?
        var renderedSignature = ""

        init(text: Binding<String>, onSelectionChange: @escaping (NSRange) -> Void) {
            self.text = text
            self.onSelectionChange = onSelectionChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            onSelectionChange(textView.selectedRange())
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onSelectionChange(textView.selectedRange())
        }
    }

    final class CanvasTextView: NSTextView {
        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }
    }
}

struct PixelCanvasEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var styleRuns: [CanvasStyleRun]
    let rowAlignments: [CanvasAlignment]
    let font: AppFont
    let baseColor: AppColor
    let basePalette: AppPalette
    @Binding var selection: NSRange
    let onSelectionChange: (NSRange) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let editor = PixelCanvasTextView()
        editor.configure(
            text: text,
            styleRuns: styleRuns,
            rowAlignments: rowAlignments,
            font: font,
            baseColor: baseColor,
            basePalette: basePalette,
            selection: selection,
            coordinator: context.coordinator
        )

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = editor
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let editor = nsView.documentView as? PixelCanvasTextView else { return }
        editor.configure(
            text: text,
            styleRuns: styleRuns,
            rowAlignments: rowAlignments,
            font: font,
            baseColor: baseColor,
            basePalette: basePalette,
            selection: selection,
            coordinator: context.coordinator
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, styleRuns: $styleRuns, selection: $selection, onSelectionChange: onSelectionChange)
    }

    final class Coordinator {
        var text: Binding<String>
        var styleRuns: Binding<[CanvasStyleRun]>
        var selection: Binding<NSRange>
        var onSelectionChange: (NSRange) -> Void

        init(text: Binding<String>, styleRuns: Binding<[CanvasStyleRun]>, selection: Binding<NSRange>, onSelectionChange: @escaping (NSRange) -> Void) {
            self.text = text
            self.styleRuns = styleRuns
            self.selection = selection
            self.onSelectionChange = onSelectionChange
        }
    }

    final class PixelCanvasTextView: NSView {
        private var text = ""
        private var styleRuns: [CanvasStyleRun] = []
        private var rowAlignments: [CanvasAlignment] = []
        private var font = AppFont.normal7
        private var baseColor = AppColor.red
        private var basePalette = AppPalette.solid
        private var selection = NSRange(location: 0, length: 0)
        private weak var coordinator: Coordinator?
        private let padding: CGFloat = 8
        private let cell: CGFloat = 5
        private let gap: CGFloat = 1
        private let rowGap: CGFloat = 8
        private var dragAnchor: Int?
        private var pagePixelWidth: Int { 80 }
        private var pageWidth: CGFloat {
            CGFloat(pagePixelWidth) * cell + CGFloat(pagePixelWidth - 1) * gap
        }

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        func configure(text: String, styleRuns: [CanvasStyleRun], rowAlignments: [CanvasAlignment], font: AppFont, baseColor: AppColor, basePalette: AppPalette, selection: NSRange, coordinator: Coordinator) {
            self.text = text
            self.styleRuns = styleRuns
            self.rowAlignments = rowAlignments
            self.font = font
            self.baseColor = baseColor
            self.basePalette = basePalette
            self.selection = selection
            self.coordinator = coordinator
            frame.size = intrinsicCanvasSize()
            needsDisplay = true
        }

        override var intrinsicContentSize: NSSize {
            intrinsicCanvasSize()
        }

    private func intrinsicCanvasSize() -> NSSize {
        let lines = displayLineInfos()
        let longest = lines.map { PixelFontRenderer.textWidth($0.text, baseStyle: font, styleRuns: lineStyleRuns(for: $0)) }.max() ?? pagePixelWidth
        let contentPixels = max(pagePixelWidth, longest)
        let contentWidth = CGFloat(contentPixels) * cell + CGFloat(max(0, contentPixels - 1)) * gap
        let width = padding * 2 + contentWidth
        let lineCount = max(7, lines.count)
        let height = padding * 2 + CGFloat(lineCount) * rowHeight + CGFloat(max(0, lineCount - 1)) * rowGap
        return NSSize(width: width, height: height)
    }

        private var rowHeight: CGFloat {
            CGFloat(7) * cell + CGFloat(6) * gap
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.setFill()
            bounds.fill()
            drawRows()
            drawSelection()
            drawPixels()
            drawCaret()
        }

        private func drawRows() {
            let count = max(7, displayLineInfos().count)
            NSColor(red: 0.02, green: 0.07, blue: 0.05, alpha: 1).setFill()
            let rowWidth = pageWidth
            for row in 0..<count {
                let y = padding + CGFloat(row) * (rowHeight + rowGap)
                let rect = NSRect(x: padding, y: y, width: rowWidth, height: rowHeight)
                NSBezierPath(rect: rect).fill()
                NSColor.systemGreen.setStroke()
                let separator = NSBezierPath()
                separator.lineWidth = 2
                separator.move(to: NSPoint(x: padding, y: y + rowHeight + 2))
                separator.line(to: NSPoint(x: padding + rowWidth, y: y + rowHeight + 2))
                separator.stroke()
            }
        }

        private func drawPixels() {
            // Render using DISPLAY text so tokens like {second} show as "45"
            for info in displayLineInfos() {
                var cursor = lineXOffsetPixels(info)
                var charIndex = 0
                for character in info.text {
                    let charFont = fontFor(globalCharacterIndex: info.start + charIndex)
                    let glyph = PixelFontRenderer.glyphRows(for: character, style: charFont)
                    let yOffset = max(0, (7 - glyph.count) / 2)
                    for (gy, row) in glyph.enumerated() {
                        for (gx, bit) in row.enumerated() where bit == "1" {
                            let pixelX = cursor + gx
                            pixelColor(globalCharacterIndex: info.start + charIndex, x: pixelX, y: yOffset + gy)
                                .setFill()
                            let rect = NSRect(
                                x: padding + CGFloat(pixelX) * (cell + gap),
                                y: info.y + CGFloat(yOffset + gy) * (cell + gap),
                                width: cell,
                                height: cell
                            )
                            NSBezierPath(roundedRect: rect, xRadius: 0.8, yRadius: 0.8).fill()
                        }
                    }
                    cursor += PixelFontRenderer.advance(for: character, glyph: glyph, style: charFont)
                    charIndex += 1
                }
            }
        }

        private func drawCaret() {
            guard window?.firstResponder === self, selection.length == 0 else { return }
            guard let info = lineInfo(containing: selection.location) ?? rawLineInfos().last else { return }
            let local = max(0, min(selection.location - info.start, (info.text as NSString).length))
            let x = padding + lineXOffsetPoints(info) + xPositionForRawOffset(local, in: info.text, lineStart: info.start)
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(x: x, y: info.y, width: 2, height: rowHeight)).fill()
        }

        private func drawSelection() {
            guard selection.length > 0 else { return }
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.45).setFill()
            for info in rawLineInfos() {
                let lineEnd = info.start + (info.text as NSString).length
                let start = max(selection.location, info.start)
                let end = min(selection.location + selection.length, lineEnd)
                guard end > start else { continue }
                let offset = lineXOffsetPoints(info)
                let x1 = offset + xPositionForRawOffset(start - info.start, in: info.text, lineStart: info.start)
                let x2 = offset + xPositionForRawOffset(end - info.start, in: info.text, lineStart: info.start)
                NSBezierPath(rect: NSRect(x: padding + x1, y: info.y, width: max(cell, x2 - x1), height: rowHeight)).fill()
            }
        }

        // MARK: - Token-safe hit-testing & coordinate mapping

        /// Map a mouse click to a raw text offset.  Never returns a position
        /// inside a dynamic token — always snaps to the nearest token boundary.
        private func characterIndex(at point: NSPoint) -> Int {
            let lines = rawLineInfos()
            guard !lines.isEmpty else { return 0 }
            let rowStep = rowHeight + rowGap
            let row = max(0, min(lines.count - 1, Int((point.y - padding) / rowStep)))
            let info = lines[row]
            let pixelX = max(0, Int((point.x - padding - lineXOffsetPoints(info)) / (cell + gap)))
            let local = rawOffsetForDisplayPixelX(pixelX, in: info.text, lineStart: info.start)
            return min((text as NSString).length, info.start + local)
        }

        /// Walk the raw line, treating each token as an atomic display-width block.
        /// Returns a raw offset that is **always** at a token boundary or character
        /// boundary, never inside a token.
        private func rawOffsetForDisplayPixelX(_ pixelX: Int, in rawLine: String, lineStart: Int) -> Int {
            var displayCursor = 0
            var rawOffset = 0
            let nsRawLine = rawLine as NSString

            while rawOffset < nsRawLine.length {
                let remaining = String(nsRawLine.substring(from: rawOffset))

                if remaining.hasPrefix("{"), let end = remaining.firstIndex(of: "}") {
                    let token = String(remaining[remaining.index(after: remaining.startIndex)..<end]).lowercased()
                    let tw = tokenDisplayPixelWidth(token)
                    let tokenRawLength = remaining.distance(from: remaining.startIndex, to: end) + 1
                    if tw > 0 {
                        let tokenWidth = tw
                        let tokenMid = displayCursor + tokenWidth / 2
                        if pixelX < tokenMid {
                            // Clicked in first half → place cursor BEFORE token
                            return rawOffset
                        }
                        if pixelX < displayCursor + tokenWidth {
                            // Clicked in second half → place cursor AFTER token
                            return rawOffset + tokenRawLength
                        }
                        // Clicked past the token entirely
                        displayCursor += tokenWidth
                        rawOffset += tokenRawLength
                        continue
                    } else {
                        // Zero-width token — invisible, skip
                        rawOffset += tokenRawLength
                        continue
                    }
                }

                // Regular character
                let char = Character(UnicodeScalar(nsRawLine.character(at: rawOffset))!)
                let charFont = fontFor(globalCharacterIndex: lineStart + rawOffset)
                let glyph = PixelFontRenderer.glyphRows(for: char, style: charFont)
                let advance = PixelFontRenderer.advance(for: char, glyph: glyph, style: charFont)
                if pixelX < displayCursor + max(1, advance / 2) {
                    return rawOffset
                }
                displayCursor += advance
                rawOffset += 1
            }
            return rawOffset
        }

        /// Compute the X coordinate for a raw offset.  If the offset falls inside
        /// a token we snap to the token start so the highlight never leaks past
        /// the visible token bounds.
        private func xPositionForRawOffset(_ offset: Int, in rawLine: String, lineStart: Int) -> CGFloat {
            var cursor = 0
            var rawOffset = 0
            let nsRawLine = rawLine as NSString

            while rawOffset < nsRawLine.length {
                let remaining = String(nsRawLine.substring(from: rawOffset))
                if remaining.hasPrefix("{"), let end = remaining.firstIndex(of: "}") {
                    let token = String(remaining[remaining.index(after: remaining.startIndex)..<end]).lowercased()
                    let tw = tokenDisplayPixelWidth(token)
                    let tokenRawLength = remaining.distance(from: remaining.startIndex, to: end) + 1
                    if tw > 0 {
                        let tokenStart = rawOffset
                        let tokenEnd = rawOffset + tokenRawLength
                        if offset > tokenStart && offset < tokenEnd {
                            // Inside a token → snap to token start
                            return CGFloat(cursor) * (cell + gap)
                        }
                        if offset >= tokenEnd {
                            cursor += tw
                            rawOffset = tokenEnd
                            continue
                        }
                        // offset == tokenStart
                        return CGFloat(cursor) * (cell + gap)
                    } else {
                        rawOffset += tokenRawLength
                        continue
                    }
                }
                if rawOffset >= offset { break }
                let char = Character(UnicodeScalar(nsRawLine.character(at: rawOffset))!)
                let charFont = fontFor(globalCharacterIndex: lineStart + rawOffset)
                let glyph = PixelFontRenderer.glyphRows(for: char, style: charFont)
                let advance = PixelFontRenderer.advance(for: char, glyph: glyph, style: charFont)
                cursor += advance
                rawOffset += 1
            }
            return CGFloat(cursor) * (cell + gap)
        }

        /// Snap a raw offset so it never sits inside a dynamic token.
        private func snapToTokenBoundary(_ offset: Int, direction: SnapDirection = .nearest) -> Int {
            let nsText = text as NSString
            guard offset > 0, offset < nsText.length else { return offset }

            // Search backward for '{'
            var search = offset
            while search > 0 {
                if nsText.character(at: search - 1) == UInt8(ascii: "{") {
                    // Found opening brace just before offset
                    // Check if there's a closing brace after offset
                    if let remaining = Range(NSRange(location: search - 1, length: nsText.length - (search - 1)), in: text),
                       let endIdx = text[remaining].firstIndex(of: "}") {
                        let tokenStart = search - 1
                        let tokenEnd = text.distance(from: remaining.lowerBound, to: endIdx) + tokenStart + 1
                        if offset < tokenEnd {
                            // offset is inside this token
                            switch direction {
                            case .start: return tokenStart
                            case .end: return tokenEnd
                            case .nearest:
                                let toStart = offset - tokenStart
                                let toEnd = tokenEnd - offset
                                return toStart <= toEnd ? tokenStart : tokenEnd
                            }
                        }
                    }
                    break
                }
                search -= 1
            }
            return offset
        }

        private enum SnapDirection {
            case start, end, nearest
        }

        private func fontFor(globalCharacterIndex: Int) -> AppFont {
            let token = styleRuns.last {
                globalCharacterIndex >= $0.location &&
                globalCharacterIndex < $0.location + $0.length &&
                Self.isFontToken($0.token)
            }?.token.lowercased()
            switch token {
            case "{font5}": return .normal5
            case "{font7}": return .normal7
            default: return font
            }
        }

        private static func isFontToken(_ token: String) -> Bool {
            ["{font5}", "{font7}"].contains(token.lowercased())
        }

        private func pixelColor(globalCharacterIndex: Int, x: Int, y: Int) -> NSColor {
            let token = styleRuns.last {
                globalCharacterIndex >= $0.location &&
                globalCharacterIndex < $0.location + $0.length &&
                !Self.isFontToken($0.token)
            }?.token.lowercased()
            switch token {
            case "{red}": return .systemRed
            case "{green}": return .systemGreen
            case "{orange}", "{yellow}": return .systemOrange
            case "{bands}":
                if y <= 1 { return .systemYellow }
                if y <= 3 { return .systemGreen }
                return .systemRed
            case "{characters}":
                return stripeColor(globalCharacterIndex)
            case "{diagonal_down}":
                return stripeColor(x + y)
            case "{diagonal_up}":
                return stripeColor(x + (6 - y))
            default:
                switch basePalette {
                case .solid:
                    return baseColor.nsColor
                case .horizontalBands:
                    if y <= 1 { return .systemYellow }
                    if y <= 3 { return .systemGreen }
                    return .systemRed
                case .characterStripes:
                    return stripeColor(globalCharacterIndex)
                case .diagonalDown:
                    return stripeColor(x + y)
                case .diagonalUp:
                    return stripeColor(x + (6 - y))
                }
            }
        }

        private func stripeColor(_ index: Int) -> NSColor {
            switch index % 3 {
            case 0: return .systemRed
            case 1: return .systemGreen
            default: return .systemYellow
            }
        }

        override func mouseDown(with event: NSEvent) {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(self)
            let location = convert(event.locationInWindow, from: nil)
            let index = characterIndex(at: location)
            dragAnchor = index
            setSelection(NSRange(location: index, length: 0))
        }

        override func scrollWheel(with event: NSEvent) {
            guard let scrollView = enclosingScrollView else {
                super.scrollWheel(with: event)
                return
            }
            let clipView = scrollView.contentView
            var origin = clipView.bounds.origin
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                origin.x += event.scrollingDeltaX
            } else if event.modifierFlags.contains(.shift) {
                origin.x -= event.scrollingDeltaY
            } else {
                origin.y -= event.scrollingDeltaY
            }
            origin.x = max(0, min(origin.x, max(0, bounds.width - clipView.bounds.width)))
            origin.y = max(0, min(origin.y, max(0, bounds.height - clipView.bounds.height)))
            clipView.scroll(to: origin)
            scrollView.reflectScrolledClipView(clipView)
        }

        private var autoScrollTimer: Timer?

        override func mouseDragged(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            let index = characterIndex(at: location)
            let anchor = dragAnchor ?? selection.location
            setSelection(NSRange(location: min(anchor, index), length: abs(index - anchor)))
            startAutoScrollIfNeeded(location: location)
        }

        override func mouseUp(with event: NSEvent) {
            dragAnchor = nil
            autoScrollTimer?.invalidate()
            autoScrollTimer = nil
        }

        private func startAutoScrollIfNeeded(location: NSPoint) {
            guard let scrollView = enclosingScrollView else { return }
            let clipView = scrollView.contentView
            let visible = clipView.bounds
            var scrollDelta = NSPoint(x: 0, y: 0)
            let margin: CGFloat = 20
            if location.x < visible.minX + margin {
                scrollDelta.x = -20
            } else if location.x > visible.maxX - margin {
                scrollDelta.x = 20
            }
            if location.y < visible.minY + margin {
                scrollDelta.y = -20
            } else if location.y > visible.maxY - margin {
                scrollDelta.y = 20
            }
            if scrollDelta.x == 0 && scrollDelta.y == 0 {
                autoScrollTimer?.invalidate()
                autoScrollTimer = nil
                return
            }
            if autoScrollTimer == nil {
                autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    self?.performAutoScroll()
                }
            }
        }

        private func performAutoScroll() {
            guard let scrollView = enclosingScrollView else { return }
            let clipView = scrollView.contentView
            var origin = clipView.bounds.origin
            let visible = clipView.bounds
            let location = window?.mouseLocationOutsideOfEventStream ?? .zero
            let local = convert(location, from: nil)
            let margin: CGFloat = 20
            if local.x < visible.minX + margin {
                origin.x -= 20
            } else if local.x > visible.maxX - margin {
                origin.x += 20
            }
            if local.y < visible.minY + margin {
                origin.y -= 20
            } else if local.y > visible.maxY - margin {
                origin.y += 20
            }
            origin.x = max(0, min(origin.x, max(0, bounds.width - visible.width)))
            origin.y = max(0, min(origin.y, max(0, bounds.height - visible.height)))
            clipView.scroll(to: origin)
            scrollView.reflectScrolledClipView(clipView)
            let index = characterIndex(at: local)
            let anchor = dragAnchor ?? selection.location
            setSelection(NSRange(location: min(anchor, index), length: abs(index - anchor)))
        }

        // MARK: - Keyboard Shortcuts & Undo

        private var undoStack: [(text: String, selection: NSRange)] = []
        private var undoIndex: Int = -1

        private func pushUndoState() {
            let state = (text: text, selection: selection)
            if undoIndex < undoStack.count - 1 {
                undoStack.removeSubrange((undoIndex + 1)...)
            }
            undoStack.append(state)
            if undoStack.count > 50 {
                undoStack.removeFirst()
            }
            undoIndex = undoStack.count - 1
        }

        private func undo() {
            guard undoIndex > 0 else { return }
            undoIndex -= 1
            let state = undoStack[undoIndex]
            text = state.text
            coordinator?.text.wrappedValue = text
            setSelection(state.selection)
            frame.size = intrinsicCanvasSize()
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }

        private func redo() {
            guard undoIndex < undoStack.count - 1 else { return }
            undoIndex += 1
            let state = undoStack[undoIndex]
            text = state.text
            coordinator?.text.wrappedValue = text
            setSelection(state.selection)
            frame.size = intrinsicCanvasSize()
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }

        override func keyDown(with event: NSEvent) {
            // Command key shortcuts
            if event.modifierFlags.contains(.command) {
                guard let chars = event.charactersIgnoringModifiers?.lowercased() else {
                    super.keyDown(with: event)
                    return
                }
                switch chars {
                case "a":
                    setSelection(NSRange(location: 0, length: (text as NSString).length))
                    return
                case "c":
                    copySelection()
                    return
                case "x":
                    copySelection()
                    if selection.length > 0 {
                        pushUndoState()
                        replaceRange(selection, with: "")
                    }
                    return
                case "z":
                    if event.modifierFlags.contains(.shift) {
                        redo()
                    } else {
                        undo()
                    }
                    return
                case "v":
                    pasteFromPasteboard()
                    return
                default:
                    super.keyDown(with: event)
                    return
                }
            }
            if handleSpecialKey(event) {
                return
            }
            guard let characters = event.charactersIgnoringModifiers else { return }
            switch characters {
            case "\u{7f}":
                pushUndoState()
                deleteBackward()
            case "\r", "\n":
                pushUndoState()
                replaceSelection(with: "\n")
            case "\u{1b}":
                break
            default:
                if event.modifierFlags.intersection([.command, .control]).isEmpty {
                    pushUndoState()
                    replaceSelection(with: characters)
                } else {
                    super.keyDown(with: event)
                }
            }
        }

        private func copySelection() {
            guard selection.length > 0 else { return }
            let nsText = text as NSString
            let selectedText = nsText.substring(with: selection)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selectedText, forType: .string)
        }

        private func pasteFromPasteboard() {
            guard let pasteText = NSPasteboard.general.string(forType: .string) else { return }
            pushUndoState()
            replaceSelection(with: pasteText)
        }

        private func handleSpecialKey(_ event: NSEvent) -> Bool {
            guard let key = event.specialKey else { return false }
            let extending = event.modifierFlags.contains(.shift)
            switch key {
            case .leftArrow:
                moveCaret(to: max(0, caretLocation - 1), extending: extending)
            case .rightArrow:
                moveCaret(to: min((text as NSString).length, caretLocation + 1), extending: extending)
            case .upArrow:
                moveVertical(direction: -1, extending: extending)
            case .downArrow:
                moveVertical(direction: 1, extending: extending)
            case .delete:
                deleteBackward()
            default:
                return false
            }
            return true
        }

        private var caretLocation: Int {
            if selection.length > 0 {
                return selection.location + selection.length
            }
            return selection.location
        }

        private func moveCaret(to newLocation: Int, extending: Bool) {
            let length = (text as NSString).length
            let clamped = max(0, min(newLocation, length))
            if extending {
                let anchor = dragAnchor ?? selection.location
                dragAnchor = anchor
                setSelection(NSRange(location: min(anchor, clamped), length: abs(clamped - anchor)))
            } else {
                dragAnchor = nil
                setSelection(NSRange(location: clamped, length: 0))
            }
        }

        private func moveVertical(direction: Int, extending: Bool) {
            let lines = rawLineInfos()
            guard let current = lineInfo(containing: caretLocation),
                  let row = lines.firstIndex(where: { $0.start == current.start }) else { return }
            let local = max(0, min(caretLocation - current.start, (current.text as NSString).length))
            let targetRow = max(0, min(lines.count - 1, row + direction))
            let target = lines[targetRow]
            let targetLocal = min(local, (target.text as NSString).length)
            moveCaret(to: target.start + targetLocal, extending: extending)
        }

        private func deleteBackward() {
            pushUndoState()
            if selection.length > 0 {
                replaceRange(selection, with: "")
            } else if selection.location > 0 {
                replaceRange(NSRange(location: selection.location - 1, length: 1), with: "")
            }
        }

        private func replaceSelection(with replacement: String) {
            replaceRange(selection, with: replacement)
        }

        private func replaceRange(_ range: NSRange, with replacement: String) {
            let nsText = text as NSString
            var safeRange = NSRange(location: max(0, min(range.location, nsText.length)), length: min(range.length, max(0, nsText.length - range.location)))
            // Snap range to token boundaries so we never split a token
            let snappedStart = snapToTokenBoundary(safeRange.location, direction: .start)
            let snappedEnd = snapToTokenBoundary(safeRange.location + safeRange.length, direction: .end)
            safeRange = NSRange(location: snappedStart, length: snappedEnd - snappedStart)
            text = nsText.replacingCharacters(in: safeRange, with: replacement)
            coordinator?.text.wrappedValue = text
            adjustStyleRuns(changedRange: safeRange, insertedLength: (replacement as NSString).length)
            setSelection(NSRange(location: safeRange.location + (replacement as NSString).length, length: 0))
            frame.size = intrinsicCanvasSize()
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }

        private func adjustStyleRuns(changedRange: NSRange, insertedLength: Int) {
            let deletedEnd = changedRange.location + changedRange.length
            let delta = insertedLength - changedRange.length
            styleRuns = styleRuns.compactMap { run in
                let runEnd = run.location + run.length
                if runEnd <= changedRange.location { return run }
                if run.location >= deletedEnd {
                    var shifted = run
                    shifted.location += delta
                    return shifted
                }
                return nil
            }
            coordinator?.styleRuns.wrappedValue = styleRuns
        }

        private func setSelection(_ range: NSRange) {
            let length = (text as NSString).length
            var snappedLocation = max(0, min(range.location, length))
            var snappedEnd = max(snappedLocation, min(range.location + range.length, length))

            // Snap to token boundaries so the cursor / selection never sits inside a token
            if snappedLocation == snappedEnd {
                // Zero-length selection (caret) — snap to nearest boundary
                snappedLocation = snapToTokenBoundary(snappedLocation, direction: .nearest)
                snappedEnd = snappedLocation
            } else {
                // Range selection — snap start to token start, end to token end
                snappedLocation = snapToTokenBoundary(snappedLocation, direction: .start)
                snappedEnd = snapToTokenBoundary(snappedEnd, direction: .end)
            }

            selection = NSRange(location: snappedLocation, length: snappedEnd - snappedLocation)
            coordinator?.selection.wrappedValue = selection
            coordinator?.onSelectionChange(selection)
            scrollSelectionIntoView()
            needsDisplay = true
        }

        private func scrollSelectionIntoView() {
            guard let info = lineInfo(containing: caretLocation) ?? rawLineInfos().last else { return }
            let local = max(0, min(caretLocation - info.start, (info.text as NSString).length))
            let x = padding + lineXOffsetPoints(info) + xPositionForRawOffset(local, in: info.text, lineStart: info.start)
            let caretRect = NSRect(x: x - 12, y: info.y, width: 36, height: rowHeight)
            scrollToVisible(caretRect)
        }

        private func lineXOffsetPixels(_ info: LineInfo) -> Int {
            let width = PixelFontRenderer.textWidth(info.text, baseStyle: font, styleRuns: lineStyleRuns(for: info))
            let free = max(0, pagePixelWidth - width)
            switch alignment(for: info.row) {
            case .left:
                return 0
            case .center:
                return free / 2
            case .right:
                return free
            }
        }

        private func lineXOffsetPoints(_ info: LineInfo) -> CGFloat {
            CGFloat(lineXOffsetPixels(info)) * (cell + gap)
        }

        private func alignment(for row: Int) -> CanvasAlignment {
            guard row >= 0, row < rowAlignments.count else { return .left }
            return rowAlignments[row]
        }

        private func lineStyleRuns(for info: LineInfo) -> [CanvasStyleRun] {
            styleRuns.compactMap { run -> CanvasStyleRun? in
                let intersectionStart = max(run.location, info.start)
                let intersectionEnd = min(run.location + run.length, info.start + (info.text as NSString).length)
                guard intersectionEnd > intersectionStart else { return nil }
                return CanvasStyleRun(
                    location: intersectionStart - info.start,
                    length: intersectionEnd - intersectionStart,
                    token: run.token
                )
            }
        }

        // MARK: - Raw / Display line helpers

        /// Line boundaries in the RAW text (for selection / hit-testing).
        private func rawLineInfos() -> [LineInfo] {
            let nsText = text as NSString
            var ranges = nsText.lineRanges
            if nsText.length > 0 {
                let last = nsText.character(at: nsText.length - 1)
                if last == 10 || last == 13 {
                    ranges.append(NSRange(location: nsText.length, length: 0))
                }
            }
            return ranges.enumerated().map { row, range in
                var contentRange = range
                while contentRange.length > 0 {
                    let last = nsText.character(at: contentRange.location + contentRange.length - 1)
                    if last == 10 || last == 13 {
                        contentRange.length -= 1
                    } else {
                        break
                    }
                }
                return LineInfo(
                    row: row,
                    start: contentRange.location,
                    text: nsText.substring(with: contentRange),
                    y: padding + CGFloat(row) * (rowHeight + rowGap)
                )
            }
        }

        /// Line boundaries in the DISPLAY text (for rendering pixels).
        private func displayLineInfos() -> [LineInfo] {
            let displayText = RescueModel.displayTextForCanvas(text)
            let nsText = displayText as NSString
            var ranges = nsText.lineRanges
            if nsText.length > 0 {
                let last = nsText.character(at: nsText.length - 1)
                if last == 10 || last == 13 {
                    ranges.append(NSRange(location: nsText.length, length: 0))
                }
            }
            return ranges.enumerated().map { row, range in
                var contentRange = range
                while contentRange.length > 0 {
                    let last = nsText.character(at: contentRange.location + contentRange.length - 1)
                    if last == 10 || last == 13 {
                        contentRange.length -= 1
                    } else {
                        break
                    }
                }
                return LineInfo(
                    row: row,
                    start: contentRange.location,
                    text: nsText.substring(with: contentRange),
                    y: padding + CGFloat(row) * (rowHeight + rowGap)
                )
            }
        }

        private func lineInfo(containing location: Int) -> LineInfo? {
            let lines = rawLineInfos()
            return lines.last { location >= $0.start && location <= $0.start + ($0.text as NSString).length }
        }

        /// Actual rendered width in LED pixel cells of a dynamic token.
        private func tokenDisplayPixelWidth(_ token: String) -> Int {
            let expanded = RescueModel.displayTextForCanvas("{\(token)}")
            guard !expanded.isEmpty else { return 0 }
            return PixelFontRenderer.textWidth(expanded, baseStyle: font, styleRuns: [])
        }

        private struct LineInfo {
            let row: Int
            let start: Int
            let text: String
            let y: CGFloat
        }
    }
}

struct NativeMultilineField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.string = text
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 8, height: 8)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .lineBorder
        scrollView.wantsLayer = true
        scrollView.layer?.borderColor = NSColor.systemGray.cgColor
        scrollView.layer?.borderWidth = 2
        scrollView.layer?.cornerRadius = 4
        scrollView.backgroundColor = NSColor.controlBackgroundColor
        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.text = $text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

struct LEDPageEditor: NSViewRepresentable {
    @Binding var text: String
    let font: AppFont
    let color: NSColor

    func makeNSView(context: Context) -> NSScrollView {
        let textView = LEDPageTextView()
        textView.string = text
        textView.font = NSFont.monospacedSystemFont(ofSize: font.editorPointSize, weight: .bold)
        textView.textColor = color
        textView.insertionPointColor = .white
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .lineBorder
        scrollView.wantsLayer = true
        scrollView.layer?.borderColor = NSColor.systemGray.cgColor
        scrollView.layer?.borderWidth = 2
        scrollView.layer?.cornerRadius = 4
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? LEDPageTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = NSFont.monospacedSystemFont(ofSize: font.editorPointSize, weight: .bold)
        textView.textColor = color
        textView.needsDisplay = true
        context.coordinator.text = $text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }

    final class LEDPageTextView: NSTextView {
        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.setFill()
            dirtyRect.fill()

            let guide = NSColor.systemGreen.withAlphaComponent(0.85)
            guide.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 2
            let lineHeight: CGFloat = 42
            var y = textContainerInset.height + lineHeight
            while y < bounds.height {
                path.move(to: NSPoint(x: 0, y: y))
                path.line(to: NSPoint(x: bounds.width, y: y))
                y += lineHeight
            }
            path.stroke()

            super.draw(dirtyRect)
        }
    }
}
