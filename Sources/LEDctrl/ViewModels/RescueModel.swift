import Foundation
import SwiftUI
import AppKit
import SigmaProtocol

@MainActor
final class RescueModel: ObservableObject {
    private static let defaultCanvasText = "RED RED RED\nGREEN GREEN\nORANGE ORANGE"
    private static let defaultCanvasStyleRuns = [
        CanvasStyleRun(location: 0, length: 11, token: "{red}"),
        CanvasStyleRun(location: 12, length: 11, token: "{green}"),
        CanvasStyleRun(location: 24, length: 13, token: "{orange}")
    ]
    private static let messageLogFileURL = URL(fileURLWithPath: "/tmp/ledctrl-message.log")
    private static let commandFileURL = URL(fileURLWithPath: "/tmp/ledctrl-command.json")
    private static let messageLogStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    @Published var selectedSection: SectionID = .messages
    @Published var serialPorts: [SerialPort] = []
    @Published var selectedSerialPortID: SerialPort.ID?
    @Published var selectedBaud = 9600
    @Published var serialProbeText = "QS:VER"
    @Published var networkProbeText = "QS:VER"
    @Published var manualIP = "192.168.11.6"
    @Published var manualPort = "9520"
    @Published var signIP = "192.168.11.6"
    @Published var signPort = "9520"
    @Published var messageText = RescueModel.defaultCanvasText
    @Published var messageRows: [MessageRow] = RescueModel.makeDefaultMessageRows()
    @Published var selectedMessageRowID: MessageRow.ID?
    @Published var selectedTextRange = NSRange(location: 0, length: 0)
    @Published var lastCanvasSelectionRange = NSRange(location: 0, length: 0)
    @Published var canvasStyleRuns: [CanvasStyleRun] = RescueModel.defaultCanvasStyleRuns
    @Published var canvasRowAlignments: [CanvasAlignment] = Array(repeating: .left, count: 7)
    @Published var messageMode = MessageMode.fitted
    @Published var messageRowsSeparate = false
    /// Effects-mode per-row overrides. Length is kept in sync with canvas
    /// line count by `syncRowEffectsToCanvasLines()`. nil = use global In/Out.
    @Published var rowEffects: [RowEffectOverride] = []

    // MARK: - Countdown Builder
    @Published var countdownTargetDate = Date().addingTimeInterval(86400)
    @Published var countdownLabel: String = "Time Remaining"
    @Published var countdownDirection: CountdownDirection = .down

    enum CountdownDirection: String, CaseIterable, Identifiable {
        case down = "down"
        case up = "up"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .down: return "Count Down"
            case .up: return "Count Up"
            }
        }
    }

    @Published var font = AppFont.normal7
    @Published var color = AppColor.red
    @Published var palette = AppPalette.solid
    @Published var inMode = SigmaEffect.all[1]
    @Published var outMode = SigmaEffect.all[1]
    @Published var speed = SigmaSpeed.mediumFast
    @Published var pauseSeconds = 2
    @Published var verticalAligns = true
    @Published var messageStatus = "Ready"
    @Published var netManagerStatus = "Ready"
    @Published var netManagerOK = false
    @Published var messageLog: [String] = []
    @Published var previewRestartSeed = Date().timeIntervalSinceReferenceDate

    // MARK: - Plex
    @Published var plexServerURL: String = UserDefaults.standard.string(forKey: "plexServerURL") ?? "http://192.168.11.22:32400" {
        didSet { UserDefaults.standard.set(plexServerURL, forKey: "plexServerURL") }
    }
    @Published var plexToken: String = UserDefaults.standard.string(forKey: "plexToken") ?? "" {
        didSet { UserDefaults.standard.set(plexToken, forKey: "plexToken") }
    }
    @Published var plexFormatTemplate: String = UserDefaults.standard.string(forKey: "plexFormatTemplate") ?? "Now Watching: {title}" {
        didSet { UserDefaults.standard.set(plexFormatTemplate, forKey: "plexFormatTemplate") }
    }
    @Published var plexNowPlaying: [PlexNowPlaying] = []
    @Published var plexStatus: String = "Not configured"
    @Published var plexAutoRefresh = false
    @Published var plexAutoSend = false
    @Published var plexMinSendInterval: Int = 60
    @Published var plexLastSentText: String = ""
    @Published var plexFont = AppFont.normal7
    @Published var plexColor = AppColor.red
    @Published var plexPalette = AppPalette.solid
    private var plexLastMediaKey: String = ""
    private var plexLastSentTime: Date = Date.distantPast
    private var plexPendingSendTask: Task<Void, Never>?
    private let plexSendDelaySeconds: TimeInterval = 10
    private var plexService = PlexService()
    private var plexRefreshTask: Task<Void, Never>?

    @Published var headlineText = ""
    @Published var headlineMode = HeadlineMode.auto
    @Published var senderProfile = SenderProfile.stable
    @Published var isSending = false
    @Published var lastSendSucceeded = false
    private var messageSendTask: Task<Void, Never>?
    @Published var playlistItems: [PlaylistItem] = []
    @Published var selectedPlaylistItem: PlaylistItem.ID?
    @Published var systemIP = "192.168.11.6"
    @Published var systemMask = "255.255.255.0"
    @Published var systemGateway = "192.168.11.1"
    @Published var systemName = "Display164"
    @Published var systemGroupAddress = 1
    @Published var systemUnitAddress = 1
    @Published var systemBaud1 = 19200
    @Published var systemBaud2 = 19200
    @Published var systemHalfBrightnessEnabled = true
    @Published var systemHalfBrightnessStart = "20:00"
    @Published var systemHalfBrightnessEnd = "06:00"
    @Published var systemPowerEnabled = false
    @Published var systemPowerOn = "13:42"
    @Published var systemPowerOff = "13:45"
    @Published var systemSerialNumber = "28008080138"
    @Published var systemLedBin = "A"
    @Published var systemShowStartupInfo = true
    @Published var systemConfigSourcePath = Paths.capturesDirectory.appendingPathComponent("systemset-after-20260502-134207/SysInfoFile").path()
    @Published var preparedConfigPath = ""
    @Published var systemStatus = "Ready to prepare a patched SysInfoFile"
    @Published var probeResults: [ProbeResult] = []
    @Published var logLines: [String] = []
    @Published var progressDurationSeconds = 10
    @Published var progressFrameCount = 11
    @Published var progressColor = AppColor.green
    @Published var progressShowsPercent = false
    @Published var progressStopAfterOneCycle = true
    @Published var progressSendEngine = ProgressSendEngine.textFallback
    @Published var progressStatus = "Ready"
    @Published var graphicsBrush = GraphicsBrush.red
    @Published var graphicsStatus = "Ready"
    @Published var graphicsPixels = Array(repeating: ProgressPixel.off, count: 80 * 7)
    @Published var foregroundOverlaySpeed = SigmaSpeed.veryFast
    @Published var foregroundOverlayUseCaptureTiming = true
    @Published var foregroundOverlayTimingCode = 0x18
    @Published var convertSourceMode = ConvertSourceMode.videoFile
    @Published var convertSourcePath = ""
    @Published var convertSequencePattern = "frame-*.png"
    @Published var convertTargetWidth = 80
    @Published var convertTargetHeight = 7
    @Published var convertFPS = 8
    @Published var convertBaseName = "movie"
    @Published var convertOutputDirectory = Paths.buildDirectory.path()
    @Published var convertLastFLVPath = ""
    @Published var convertLastFLWPath = ""
    @Published var convertStatus = "Ready"
    private var commandWatcherTask: Task<Void, Never>?

    private struct RuntimeCommand: Decodable {
        var action: String
        var duration: Int?
        var frames: Int?
        var engine: String?
        var stopAfterOneCycle: Bool?
    }

    init() {
        selectedMessageRowID = messageRows.first?.id
        startRuntimeCommandWatcher()
        appendMessageLog("Runtime log file: \(Self.messageLogFileURL.path())")
        appendMessageLog("Runtime command file: \(Self.commandFileURL.path())")
    }

    var normalizedMessageText: String {
        Self.sanitizeSignText(serializedCanvasText)
    }

    var progressPreviewFrame: PixelFontRenderer.RenderedPixels {
        Self.progressFrame(fill: 0.5, color: progressColor, showsPercent: progressShowsPercent).renderedPixels
    }

    var graphicsPreviewFrame: PixelFontRenderer.RenderedPixels {
        let bools = (0..<7).map { y in
            (0..<80).map { x in graphicsPixels[y * 80 + x] != .off }
        }
        let indexes = Array(repeating: Array<Int?>(repeating: nil, count: 80), count: 7)
        return PixelFontRenderer.RenderedPixels(pixels: bools, characterIndexes: indexes)
    }

    var previewMessageText: String {
        Self.previewText(from: Self.sanitizeSignText(Self.displayTextForCanvas(messageText)))
    }

    private var serializedCanvasText: String {
        Self.expandAppOnlyDateTokens(Self.serializeCanvasText(
            messageText,
            styleRuns: canvasStyleRuns,
            colorRestoreToken: restoreToken(),
            fontRestoreToken: restoreFontToken()
        ))
    }

    var canvasLineCount: Int {
        max(1, messageText.components(separatedBy: .newlines).count)
    }

    /// Resize `rowEffects` to match the current canvas line count. Called
    /// whenever the canvas text changes; preserves existing per-row settings
    /// in place and appends defaults for new rows.
    func syncRowEffectsToCanvasLines() {
        let target = canvasLineCount
        if rowEffects.count == target { return }
        if rowEffects.count < target {
            let inDefault = inMode
            let outDefault = outMode
            for _ in rowEffects.count..<target {
                rowEffects.append(RowEffectOverride(inMode: inDefault, outMode: outDefault))
            }
        } else {
            rowEffects.removeLast(rowEffects.count - target)
        }
    }

    /// Build the wire-format per-row override array consumed by SigmaTextOptions
    /// for Effects mode. Disabled rows pass nil so the renderer falls back to
    /// the global In/Out from the NMG header. Middle rows (not first or last)
    /// only emit an IN override; OUT for middle rows always falls back to global.
    func wireRowEffects() -> [SigmaTextOptions.RowEffect?] {
        let total = rowEffects.count
        return rowEffects.enumerated().map { index, override in
            guard override.enabled else { return nil }
            let isEdge = (index == 0 || index == total - 1)
            return SigmaTextOptions.RowEffect(
                inEffectCode: override.inMode.sigmaCode,
                outEffectCode: isEdge ? override.outMode.sigmaCode : nil
            )
        }
    }

    var activeCanvasAlignment: CanvasAlignment {
        let row = activeCanvasRowIndex
        guard row >= 0, row < canvasRowAlignments.count else { return .left }
        return canvasRowAlignments[row]
    }

    private var activeCanvasRowIndex: Int {
        let caret = selectedTextRange.location
        let nsText = messageText as NSString
        let ranges = nsText.lineRanges
        guard !ranges.isEmpty else { return 0 }
        for (index, range) in ranges.enumerated() {
            if caret >= range.location && caret < range.location + range.length {
                return index
            }
        }
        return max(0, ranges.count - 1)
    }

    private var selectedCanvasRowIndexes: [Int] {
        let selection = selectedTextRange
        let nsText = messageText as NSString
        let ranges = nsText.lineRanges
        guard !ranges.isEmpty else { return [0] }
        var indexes: [Int] = []
        for (index, range) in ranges.enumerated() {
            let selectionEnd = selection.location + selection.length
            let rangeEnd = range.location + range.length
            if selection.location < rangeEnd && selectionEnd > range.location {
                indexes.append(index)
            }
        }
        return indexes.isEmpty ? [max(0, ranges.count - 1)] : indexes
    }

    private func serializedCanvasLines() -> [String] {
        canvasLinePayloads().map(\.serializedText)
    }

    private func canvasLinePayloads() -> [CanvasLinePayload] {
        let nsText = messageText as NSString
        return nsText.lineRanges.enumerated().compactMap { rowIndex, lineRange in
            var contentRange = lineRange
            while contentRange.length > 0 {
                let last = nsText.character(at: contentRange.location + contentRange.length - 1)
                if last == 10 || last == 13 {
                    contentRange.length -= 1
                } else {
                    break
                }
            }

            let rawLine = nsText.substring(with: contentRange)
            guard !rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let lineRuns = styleRuns(in: contentRange)
            let serialized = Self.expandAppOnlyDateTokens(Self.serializeCanvasText(
                rawLine,
                styleRuns: lineRuns,
                colorRestoreToken: restoreToken(),
                fontRestoreToken: restoreFontToken()
            ))
            let displayText = Self.displayTextForCanvas(rawLine)
            return CanvasLinePayload(
                rowIndex: rowIndex,
                rawText: displayText,
                serializedText: serialized,
                styleRuns: lineRuns,
                alignment: alignmentForCanvasRow(rowIndex)
            )
        }
    }

    private func alignmentForCanvasRow(_ row: Int) -> CanvasAlignment {
        guard row >= 0, row < canvasRowAlignments.count else { return .left }
        return canvasRowAlignments[row]
    }

    private func styleRuns(in contentRange: NSRange) -> [CanvasStyleRun] {
        canvasStyleRuns.compactMap { run -> CanvasStyleRun? in
                let start = max(run.location, contentRange.location)
                let end = min(run.location + run.length, contentRange.location + contentRange.length)
                guard end > start else { return nil }
                return CanvasStyleRun(location: start - contentRange.location, length: end - start, token: run.token)
        }
    }

    func canvasPixelContentWidth(height: CGFloat) -> CGFloat {
        let rowHeight = max(18, (height - 18) / 7)
        let longest = messageText
            .components(separatedBy: .newlines)
            .enumerated()
            .map { _, line in PixelFontRenderer.textWidth(line, style: font) + 2 }
            .max() ?? 80
        return rowHeight * CGFloat(max(80, longest)) / 7.0 + 16
    }

    var activeMessageRows: [MessageRow] {
        messageRows
            .sorted { $0.order < $1.order }
            .filter { !Self.sanitizeSignText($0.text).isEmpty }
    }

    var selectedMessageRow: MessageRow {
        if let selectedMessageRowID,
           let row = messageRows.first(where: { $0.id == selectedMessageRowID }) {
            return row
        }
        return messageRows.first ?? MessageRow(
            order: 0,
            text: "",
            mode: messageMode,
            font: font,
            color: color,
            palette: palette,
            inMode: inMode,
            outMode: outMode,
            speed: speed,
            pauseSeconds: pauseSeconds
        )
    }

    var selectedRowPreviewText: String {
        previewMessageText
    }

    var selectedRowIndex: Int {
        messageRows.firstIndex(where: { $0.id == selectedMessageRow.id }) ?? 0
    }

    func restartPreviewAnimation() {
        previewRestartSeed = Date().timeIntervalSinceReferenceDate
    }

    var normalizedHeadlineLines: [String] {
        headlineText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { Self.sanitizeSignText(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    var firstHeadlinePreview: String {
        normalizedHeadlineLines.first ?? ""
    }

    var headlineLineCount: Int {
        normalizedHeadlineLines.count
    }

    func refreshDevices() {
        let devURL = URL(fileURLWithPath: "/dev")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: devURL.path())) ?? []
        let ports = names
            .filter { $0.hasPrefix("cu.") }
            .sorted()
            .map { name in
                let path = "/dev/\(name)"
                let hint = name.contains("usbmodem") ? "CDC USB serial candidate" : "Serial device"
                return SerialPort(path: path, hint: hint)
            }
        serialPorts = ports
        if selectedSerialPortID == nil {
            selectedSerialPortID = (ports.first { $0.path.contains("usbmodem") } ?? ports.first)?.id
        }
        addLog("Found \(ports.count) serial port(s).")
    }

    func probeSelectedSerial() {
        guard let port = selectedSerialPort else { return }
        let command = serialProbeText
        let baud = selectedBaud
        addLog("Serial probe \(port.path) @ \(baud): \(command)")
        Task.detached {
            let response = SerialProbe.probe(path: port.path, baud: baud, text: command)
            await MainActor.run {
                self.addLog(response)
            }
        }
    }

    func probeManualTCP() {
        guard let port = UInt16(manualPort) else {
            addLog("Invalid port: \(manualPort)")
            return
        }
        probeTCP(host: manualIP, port: port, text: networkProbeText)
    }

    func probeSignStatus() {
        guard let port = UInt16(signPort) else {
            appendMessageLog("Invalid port: \(signPort)")
            return
        }
        messageStatus = "Probing \(signIP):\(port)"
        Task.detached {
            let response = await TCPProbe.probe(host: self.signIP, port: port, text: "QS:VER")
            await MainActor.run {
                self.lastSendSucceeded = response.ok
                self.messageStatus = response.ok ? "Sign is reachable" : "Probe failed"
                self.appendMessageLog("Probe \(self.signIP):\(port): \(response.message)")
            }
        }
    }

    func checkKnownSign() {
        guard let port = UInt16(signPort) else {
            netManagerOK = false
            netManagerStatus = "Invalid port: \(signPort)"
            return
        }
        let host = signIP
        let target = "\(host):\(port)"
        netManagerOK = false
        netManagerStatus = "Checking \(target)"
        probeResults.append(ProbeResult(target: target, status: "Trying", response: "Net Manager check"))

        Task.detached {
            let response = await TCPProbe.probe(host: host, port: port, text: "QS:VER")
            await MainActor.run {
                self.netManagerOK = response.ok
                self.netManagerStatus = response.ok ? "Sign reachable at \(target)" : "No response from \(target)"
                if let idx = self.probeResults.lastIndex(where: { $0.target == target && $0.status == "Trying" }) {
                    self.probeResults[idx] = ProbeResult(
                        target: target,
                        status: response.ok ? "Reachable" : "No response",
                        response: response.message
                    )
                }
                self.addLog("Net Manager \(target): \(response.message)")
            }
        }
    }

    func sendCurrentMessage() {
        guard !isSending else { return }
        normalizeVisibleCanvasMarkupIfNeeded()
        guard let port = UInt16(signPort) else {
            appendMessageLog("Invalid port: \(signPort)")
            return
        }

        let host = signIP
        let canvasLines = canvasLinePayloads()
        let canvasText = canvasLines
            .map { Self.textOnlySerializedLine($0.serializedText) }
            .joined(separator: "\n")
        let canvasMode = messageMode
        let canvasFont = font
        let canvasColor = palette.sendColor(base: color)
        let canvasPalette = palette
        let canvasInMode = inMode
        let canvasOutMode = outMode
        let canvasSpeed = speed
        let canvasHold = pauseSeconds
        let canvasVerticalAligns = verticalAligns
        let canvasAlignment = alignmentForCanvasRow(0)
        let useEditorFontCompat = senderProfile == .editorFont
        syncRowEffectsToCanvasLines()
        let canvasPerRowEffects: [SigmaTextOptions.RowEffect?]? =
            (canvasMode == .slides && rowEffects.contains(where: { $0.enabled }))
                ? wireRowEffects()
                : nil
        guard !canvasLines.isEmpty else { return }

        isSending = true
        previewRestartSeed = Date().timeIntervalSinceReferenceDate
        lastSendSucceeded = false
        messageStatus = "Sending canvas to \(host)"
        appendMessageLog("Sending canvas")

        messageSendTask?.cancel()
        messageSendTask = Task.detached {
            do {
                var client = SigmaClient(host: host, port: port)
                var allSteps: [String] = []
                allSteps.append("Canvas rows: \(canvasLines.count)")
                allSteps.append("Style: \(canvasMode.label), \(canvasFont.label), \(canvasPalette.label), speed=\(canvasSpeed.label), hold=\(canvasHold)s, vertical=\(canvasVerticalAligns ? "center" : "off")")
                let safeText = Self.sanitizeSignText(canvasText)
                allSteps.append("Program: \(Self.stripZeroWidthMarkup(from: safeText).replacingOccurrences(of: "\n", with: " / "))")

                allSteps.append(contentsOf: try client.sendText(
                    safeText,
                    font: canvasFont.sigmaFont,
                    color: canvasColor,
                    options: Self.optionsForCanvas(
                        mode: canvasMode,
                        inMode: canvasInMode,
                        outMode: canvasOutMode,
                        speed: canvasSpeed,
                        holdSeconds: canvasHold,
                        verticalAligns: canvasVerticalAligns,
                        alignment: canvasAlignment,
                        perRowEffects: canvasPerRowEffects
                    ),
                    editorFontCompat: useEditorFontCompat
                ))

                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = true
                    self.messageStatus = "Sent \(canvasLines.count) row(s)"
                    self.messageSendTask = nil
                    for step in allSteps {
                        self.appendMessageLog(step)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = false
                    self.messageStatus = "Send failed"
                    self.messageSendTask = nil
                    self.appendMessageLog("Error: \(error)")
                }
            }
        }
    }

    func loadProjectHeadlines() {
        let url = URL(fileURLWithPath: Paths.todaysHeadlines.path())
        do {
            headlineText = try String(contentsOf: url, encoding: .utf8)
            appendMessageLog("Loaded headlines from \(url.path())")
        } catch {
            appendMessageLog("Could not load project headlines: \(error)")
        }
    }

    func chooseHeadlineFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                headlineText = try String(contentsOf: url, encoding: .utf8)
                appendMessageLog("Loaded headlines from \(url.path())")
            } catch {
                appendMessageLog("Could not load \(url.path()): \(error)")
            }
        }
    }

    func sendHeadlineLines() {
        guard !isSending else { return }
        guard let port = UInt16(signPort) else {
            appendMessageLog("Invalid port: \(signPort)")
            return
        }

        let lines = normalizedHeadlineLines
        guard !lines.isEmpty else { return }

        let host = signIP
        let font = font.sigmaFont
        let color = color.sigmaColor
        let mode = headlineMode
        let speed = speed
        let holdSeconds = pauseSeconds
        let useEditorFontCompat = senderProfile == .editorFont

        isSending = true
        previewRestartSeed = Date().timeIntervalSinceReferenceDate
        lastSendSucceeded = false
        messageStatus = "Sending \(lines.count) headline(s)"
        appendMessageLog("Sending \(lines.count) headline line(s) as \(mode.label)")

        Task.detached {
            do {
                var client = SigmaClient(host: host, port: port)
                var allSteps: [String] = []
                for (index, line) in lines.enumerated() {
                    let options = Self.optionsForHeadline(
                        line,
                        mode: mode,
                        font: font,
                        speed: speed,
                        holdSeconds: holdSeconds
                    )
                    allSteps.append("Headline \(index + 1)/\(lines.count): \(line)")
                    allSteps.append(contentsOf: try client.sendText(
                        line,
                        font: font,
                        color: color,
                        options: options,
                        editorFontCompat: useEditorFontCompat
                    ))
                    if index < lines.count - 1 {
                        try await Task.sleep(nanoseconds: 350_000_000)
                    }
                }

                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = true
                    self.messageStatus = "Headlines sent"
                    for step in allSteps {
                        self.appendMessageLog(step)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = false
                    self.messageStatus = "Headline send failed"
                    self.appendMessageLog("Error: \(error)")
                }
            }
        }
    }

    func sendProgressBar(fill: Double) {
        sendProgressFrames([max(0, min(1, fill))], durationSeconds: 0)
    }

    func sendProgressAnimation() {
        let requestedFrames = max(2, progressFrameCount)
        let frames: Int
        if progressSendEngine == .backgroundReplay {
            let templateFrames = max(2, Self.noBlackTemplateFrameCount() ?? 10)
            frames = min(requestedFrames, templateFrames)
            if requestedFrames != frames {
                appendMessageLog("Progress frame cap: requested \(requestedFrames), using \(frames) (firmware sequence limit)")
            }
        } else {
            frames = requestedFrames
        }
        let fills = (0..<frames).map { index in
            Double(index) / Double(frames - 1)
        }
        sendProgressFrames(fills, durationSeconds: progressDurationSeconds)
    }

    func paintGraphicsPixel(x: Int, y: Int) {
        guard x >= 0, x < 80, y >= 0, y < 7 else { return }
        let index = y * 80 + x
        let pixel = graphicsBrushPixel()
        guard graphicsPixels[index] != pixel else { return }
        graphicsPixels[index] = pixel
    }

    func clearGraphicsPixels() {
        graphicsPixels = Array(repeating: .off, count: 80 * 7)
        graphicsStatus = "Cleared"
    }

    func checkerGraphicsPreset() {
        var next = Array(repeating: ProgressPixel.off, count: 80 * 7)
        for y in 0..<7 {
            for x in 0..<80 {
                if (x + y) % 2 == 0 {
                    next[y * 80 + x] = .green
                } else if x % 4 == 0 {
                    next[y * 80 + x] = .orange
                }
            }
        }
        graphicsPixels = next
        graphicsStatus = "Loaded checker preset"
    }

    func chevronGraphicsPreset() {
        var next = Array(repeating: ProgressPixel.off, count: 80 * 7)

        func set(_ x: Int, _ y: Int, _ pixel: ProgressPixel) {
            guard x >= 0, x < 80, y >= 0, y < 7 else { return }
            next[y * 80 + x] = pixel
        }

        for y in 0..<7 {
            let dx = y <= 3 ? y : 6 - y
            set(2 + dx, y, .red)
        }
        for y in 1...5 {
            let dy = y - 1
            let dx = dy <= 2 ? dy : 4 - dy
            set(12 + dx, y, .green)
        }
        for y in 2...4 {
            let dy = y - 2
            let dx = dy <= 1 ? dy : 2 - dy
            set(20 + dx, y, .orange)
        }
        set(26, 3, .red)
        set(28, 3, .green)
        set(30, 3, .orange)

        graphicsPixels = next
        graphicsStatus = "Loaded chevron preset"
    }

    func sendForegroundTextOnly() {
        guard !isSending else { return }
        guard let port = UInt16(signPort) else {
            appendMessageLog("Invalid port: \(signPort)")
            return
        }

        let lines = canvasLinePayloads().filter { !$0.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !lines.isEmpty else {
            appendMessageLog("Foreground overlay skipped: no non-empty canvas rows")
            return
        }

        guard let family = Self.loadBackgroundReplayFamilyForProgress() else {
            appendMessageLog("Foreground overlay blocked: no background template family available")
            return
        }

        let host = signIP
        let basePixels = graphicsPixels
        let baseFont = font
        let baseColor = color
        let basePalette = palette
        let overlayMode = messageMode
        let overlayInMode = inMode
        let overlayOutMode = outMode
        let useEditorFontCompat = senderProfile == .editorFont
        let effectiveSpeed: SigmaSpeed = overlayMode == .marquee ? .veryFast : foregroundOverlaySpeed
        let speedCode = effectiveSpeed.sigmaCode
        let speedLabel = effectiveSpeed.label
        let holdSeconds = overlayMode == .marquee ? 1 : max(1, pauseSeconds)
        let useCaptureTiming = foregroundOverlayUseCaptureTiming
        let manualTimingCode = UInt8(max(1, min(255, foregroundOverlayTimingCode)))

        isSending = true
        lastSendSucceeded = false
        graphicsStatus = "Sending foreground overlay program"
        messageStatus = graphicsStatus
        appendMessageLog("Foreground overlay: building \(lines.count) frame(s) over current canvas background")

        Task.detached {
            do {
                var client = SigmaClient(host: host, port: port)
                var allSteps: [String] = []

                if overlayMode == .marquee {
                    let text = lines.map(\.rawText).joined(separator: "   ")
                    let options = Self.optionsForCanvas(
                        mode: .marquee,
                        inMode: overlayInMode,
                        outMode: overlayOutMode,
                        speed: effectiveSpeed,
                        holdSeconds: holdSeconds,
                        verticalAligns: false,
                        alignment: .left
                    )
                    allSteps.append("Firmware limit: temp.Nmg/background image programs do not support marquee on this sign")
                    allSteps.append("Foreground marquee fallback: using native text marquee engine (replaces active background program)")
                    allSteps.append("Foreground overlay family: native marquee text engine")
                    allSteps.append("Foreground marquee text: \(text)")
                    allSteps.append("Foreground marquee timing: hold=\(holdSeconds)s speed=\(speedLabel)")
                    allSteps.append(contentsOf: try client.sendText(
                        text,
                        font: baseFont.sigmaFont,
                        color: basePalette.sendColor(base: baseColor),
                        options: options,
                        editorFontCompat: useEditorFontCompat
                    ))

                    await MainActor.run {
                        self.isSending = false
                        self.lastSendSucceeded = true
                        self.graphicsStatus = "Foreground marquee sent"
                        self.messageStatus = self.graphicsStatus
                        for step in allSteps {
                            self.appendMessageLog(step)
                        }
                    }
                    return
                }

                allSteps.append("Foreground overlay family: \(family.label)")
                allSteps.append("Foreground overlay timing: hold=\(holdSeconds)s speed=\(speedLabel)")
                let capturedTimingCode = Self.rowChange120SequenceTimingCode()
                let sequenceTimingCode: UInt8 = {
                    if useCaptureTiming {
                        return capturedTimingCode ?? manualTimingCode
                    }
                    return manualTimingCode
                }()
                let preserveTemplateTiming = useCaptureTiming
                allSteps.append(
                    String(
                        format: "Foreground sequence timing code: 0x%02X (%d)%@",
                        sequenceTimingCode,
                        sequenceTimingCode,
                        useCaptureTiming && capturedTimingCode != nil ? " (from row-change 120ms capture)" : ""
                    )
                )
                let replayBuild = try Self.makeNoBlackForegroundOverlayReplayPackets(
                    lines: lines,
                    mode: overlayMode,
                    basePixels: basePixels,
                    baseFont: baseFont,
                    baseColor: baseColor,
                    basePalette: basePalette,
                    speedCode: speedCode,
                    holdSeconds: holdSeconds,
                    sequenceTimingCode: sequenceTimingCode,
                    preserveTemplateTiming: preserveTemplateTiming
                )
                allSteps.append("Foreground overlay frames: \(replayBuild.frameCount)")
                allSteps.append(contentsOf: replayBuild.debugLines)
                allSteps.append("Foreground overlay packets: strict one-shot wire replay")
                allSteps.append(contentsOf: try client.replayCapturedPackets(replayBuild.build.packets))

                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = true
                    self.graphicsStatus = "Foreground overlay sent"
                    self.messageStatus = self.graphicsStatus
                    for step in allSteps {
                        self.appendMessageLog(step)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = false
                    self.graphicsStatus = "Foreground overlay failed"
                    self.messageStatus = self.graphicsStatus
                    self.appendMessageLog("Foreground overlay error: \(error)")
                }
            }
        }
    }

    func replayEditorRowChange120Capture() {
        guard !isSending else { return }
        guard let port = UInt16(signPort) else {
            appendMessageLog("Invalid port: \(signPort)")
            return
        }
        guard let packets = Self.loadEditorRowChange120ReplayPackets() else {
            appendMessageLog("Replay blocked: row-change 120ms capture not found")
            return
        }

        let host = signIP
        isSending = true
        lastSendSucceeded = false
        graphicsStatus = "Replaying 120ms capture"
        messageStatus = graphicsStatus
        appendMessageLog("Replay: editor row-change 120ms capture")

        Task.detached {
            do {
                var client = SigmaClient(host: host, port: port)
                let steps = try client.replayCapturedPackets(packets)
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = true
                    self.graphicsStatus = "120ms capture replayed"
                    self.messageStatus = self.graphicsStatus
                    self.appendMessageLog("Replay packets: \(packets.count)")
                    for step in steps {
                        self.appendMessageLog(step)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = false
                    self.graphicsStatus = "120ms replay failed"
                    self.messageStatus = self.graphicsStatus
                    self.appendMessageLog("Replay error: \(error)")
                }
            }
        }
    }

    func sendGraphicsBackgroundFrame() {
        guard !isSending else { return }
        guard let port = UInt16(signPort) else {
            appendMessageLog("Invalid port: \(signPort)")
            return
        }

        let templatePair =
            Self.loadBackgroundReplayFamilyForProgress()?.templatePair
            ?? Self.loadEditorBackgroundTemplatePairWithBMP()
            ?? Self.loadEditorBackgroundTemplatePair()
        guard let templatePair else {
            graphicsStatus = "No Editor background template found"
            messageStatus = graphicsStatus
            appendMessageLog("Background send blocked: no temp.Nmg + SequentList.tmps template pair found.")
            return
        }

        let host = signIP
        let pixels = graphicsPixels
        let backgroundHold = max(1, pauseSeconds)
        let replayBuild = try? Self.makeBackgroundReplayPackets(
            pixels: pixels,
            speedCode: speed.sigmaCode,
            holdSeconds: backgroundHold,
            includeSetup: true
        )
        isSending = true
        lastSendSucceeded = false
        graphicsStatus = "Setting persistent background"
        messageStatus = graphicsStatus
        if let replayBuild {
            appendMessageLog("Background: sending canvas background via patched replay (\(replayBuild.familyLabel))")
        } else {
            appendMessageLog("Background: sending canvas background from \(templatePair.sourceLabel)")
        }
        if let payloadLength = templatePair.payloadLength {
            appendMessageLog("Background payload length: \(payloadLength) bytes")
        }

        Task.detached {
            do {
                var client = SigmaClient(host: host, port: port)
                let steps: [String]
                if let replayBuild {
                    steps = try client.replayCapturedPackets(replayBuild.packets)
                } else {
                    let bmp = BitmapGenerator.makeRGB565BMP(width: 80, height: 7, pixels: pixels)
                    let program = Self.replaceBmp(
                        inTemplateNmg: templatePair.nmg,
                        with: bmp,
                        trimAfterBmp: false
                    ) ?? Self.replaceAllBmps(
                        inTemplateNmg: templatePair.nmg,
                        with: bmp,
                        trimAfterFirstBmp: false
                    ) ?? templatePair.nmg
                    steps = try client.sendEditorProgramNmg(
                        program,
                        filename: "temp.Nmg",
                        sequenceFileOverride: templatePair.sequence,
                        payloadLengthOverride: templatePair.payloadLength
                    )
                }
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = true
                    self.graphicsStatus = "Background sent"
                    self.messageStatus = self.graphicsStatus
                    if let replayBuild {
                        self.appendMessageLog("Background source: patched replay (\(replayBuild.familyLabel))")
                    } else {
                        self.appendMessageLog("Background source: \(templatePair.sourceLabel)")
                    }
                    for step in steps {
                        self.appendMessageLog(step)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = false
                    self.graphicsStatus = "Background send failed"
                    self.messageStatus = self.graphicsStatus
                    self.appendMessageLog("Background error: \(error)")
                }
            }
        }
    }

    func sendGraphicsFrame() {
        guard !isSending else { return }
        guard let port = UInt16(signPort) else {
            appendMessageLog("Invalid port: \(signPort)")
            return
        }

        let host = signIP
        let pixels = graphicsPixels
        isSending = true
        lastSendSucceeded = false
        graphicsStatus = "Sending graphic frame"
        messageStatus = graphicsStatus
        appendMessageLog("Graphics: sending 80x7 picture frame")

        Task.detached {
            do {
                var client = SigmaClient(host: host, port: port)
                let nmg = Self.makePictureNmg(width: 80, height: 7, pixels: pixels)
                let steps = try client.sendNmg(nmg, filename: "temp.Nmg", fileType: .text)
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = true
                    self.graphicsStatus = "Graphic frame sent"
                    self.messageStatus = self.graphicsStatus
                    for step in steps {
                        self.appendMessageLog(step)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = false
                    self.graphicsStatus = "Graphic send failed"
                    self.messageStatus = self.graphicsStatus
                    self.appendMessageLog("Graphics error: \(error)")
                }
            }
        }
    }

    func saveGraphicsPNG() {
        let exportScale = 2
        let exportWidth = 80 * exportScale
        let exportHeight = 7 * exportScale
        let panel = NSSavePanel()
        panel.title = "Save \(exportWidth)x\(exportHeight) PNG"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "frame-\(Self.pngTimestampString()).png"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else {
            graphicsStatus = "PNG save canceled"
            return
        }

        do {
            let png = try BitmapGenerator.makeGraphicsPNG(width: 80, height: 7, pixels: graphicsPixels, scale: exportScale)
            try png.write(to: url, options: .atomic)
            graphicsStatus = "Saved PNG: \(url.lastPathComponent)"
            messageStatus = graphicsStatus
            appendMessageLog("Graphics PNG saved: \(url.path)")
        } catch {
            graphicsStatus = "PNG save failed"
            messageStatus = graphicsStatus
            appendMessageLog("Graphics PNG save error: \(error)")
        }
    }

    func loadGraphicsPNG() {
        let panel = NSOpenPanel()
        panel.title = "Load PNG as 80x7 Frame"
        panel.allowedContentTypes = [.png]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            graphicsStatus = "PNG load canceled"
            return
        }

        do {
            graphicsPixels = try BitmapGenerator.loadGraphicsPixels(from: url, width: 80, height: 7)
            graphicsStatus = "Loaded PNG: \(url.lastPathComponent)"
            messageStatus = graphicsStatus
            appendMessageLog("Graphics PNG loaded: \(url.path)")
        } catch {
            graphicsStatus = "PNG load failed"
            messageStatus = graphicsStatus
            appendMessageLog("Graphics PNG load error: \(error)")
        }
    }

    func chooseConvertSource() {
        switch convertSourceMode {
        case .videoFile:
            let panel = NSOpenPanel()
            panel.title = "Choose Video File"
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                convertSourcePath = url.path()
                convertStatus = "Selected video: \(url.lastPathComponent)"
                appendMessageLog("Convert source video: \(url.path())")
            }
        case .pngSequenceFolder:
            let panel = NSOpenPanel()
            panel.title = "Choose PNG Sequence Folder"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                convertSourcePath = url.path()
                convertStatus = "Selected folder: \(url.lastPathComponent)"
                appendMessageLog("Convert source folder: \(url.path())")
            }
        }
    }

    func chooseConvertOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Output Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            convertOutputDirectory = url.path()
            convertStatus = "Output folder selected"
            appendMessageLog("Convert output folder: \(url.path())")
        }
    }

    func convertMediaToSignMovie() {
        guard !isSending else { return }

        let sourceMode = convertSourceMode
        let sourcePath = convertSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = convertSequencePattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputDirectory = convertOutputDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetWidth = max(8, convertTargetWidth)
        let targetHeight = max(7, convertTargetHeight)
        let fps = max(1, convertFPS)
        let baseName = Self.sanitizedFilenameStem(convertBaseName, fallback: "movie")

        guard !sourcePath.isEmpty else {
            convertStatus = "Missing source"
            appendMessageLog("Convert error: source path is empty")
            return
        }
        guard !outputDirectory.isEmpty else {
            convertStatus = "Missing output folder"
            appendMessageLog("Convert error: output folder is empty")
            return
        }
        if sourceMode == .pngSequenceFolder && pattern.isEmpty {
            convertStatus = "Missing PNG pattern"
            appendMessageLog("Convert error: PNG sequence pattern is empty")
            return
        }

        isSending = true
        lastSendSucceeded = false
        convertStatus = "Converting..."
        messageStatus = "Converting media"
        appendMessageLog("Convert: mode=\(sourceMode.rawValue), target=\(targetWidth)x\(targetHeight), fps=\(fps)")

        Task.detached {
            do {
                let ffmpegPath = try MediaConverter.resolveFFmpegPath()
                let timestamp = Self.pngTimestampString()
                let outputDirURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
                try FileManager.default.createDirectory(at: outputDirURL, withIntermediateDirectories: true)

                let flvURL = outputDirURL.appendingPathComponent("\(baseName)-\(timestamp).flv")
                let flwURL = outputDirURL.appendingPathComponent("\(baseName)-\(timestamp).FLW")
                let scaleFilter = "scale=\(targetWidth):\(targetHeight):flags=neighbor,format=yuv420p"

                let args: [String]
                switch sourceMode {
                case .videoFile:
                    args = [
                        "-y",
                        "-i", sourcePath,
                        "-vf", scaleFilter,
                        "-r", "\(fps)",
                        "-c:v", "flv1",
                        flvURL.path()
                    ]
                case .pngSequenceFolder:
                    let inputPattern = URL(fileURLWithPath: sourcePath, isDirectory: true)
                        .appendingPathComponent(pattern)
                        .path()
                    args = [
                        "-y",
                        "-framerate", "\(fps)",
                        "-pattern_type", "glob",
                        "-i", inputPattern,
                        "-vf", scaleFilter,
                        "-c:v", "flv1",
                        flvURL.path()
                    ]
                }

                let output = try MediaConverter.runProcess(executable: ffmpegPath, arguments: args)
                if FileManager.default.fileExists(atPath: flwURL.path()) {
                    try FileManager.default.removeItem(at: flwURL)
                }
                try FileManager.default.copyItem(at: flvURL, to: flwURL)

                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = true
                    self.convertLastFLVPath = flvURL.path()
                    self.convertLastFLWPath = flwURL.path()
                    self.convertStatus = "Converted \(flwURL.lastPathComponent)"
                    self.messageStatus = self.convertStatus
                    self.appendMessageLog("Convert done: \(flvURL.path())")
                    self.appendMessageLog("FLW copy: \(flwURL.path())")
                    for line in MediaConverter.summarizeProcessOutput(output) {
                        self.appendMessageLog("ffmpeg: \(line)")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = false
                    self.convertStatus = "Convert failed"
                    self.messageStatus = self.convertStatus
                    self.appendMessageLog("Convert error: \(error)")
                }
            }
        }
    }

    func sendConvertedMovieToSign() {
        guard !isSending else { return }
        guard let port = UInt16(signPort) else {
            appendMessageLog("Invalid port: \(signPort)")
            return
        }
        guard !convertLastFLWPath.isEmpty else {
            convertStatus = "No converted FLW to send"
            return
        }

        let host = signIP
        let path = convertLastFLWPath
        isSending = true
        lastSendSucceeded = false
        convertStatus = "Sending movie..."
        messageStatus = convertStatus
        appendMessageLog("Send movie: \(path) -> \(host):\(port)")

        Task.detached {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                var client = SigmaClient(host: host, port: port)
                let remoteName = Self.makeSigma83MovieFilename(from: URL(fileURLWithPath: path).lastPathComponent)
                await MainActor.run {
                    self.appendMessageLog("Movie remote name: \(remoteName)")
                }
                let steps = try client.sendNmg(data, filename: remoteName, fileType: .flw)
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = true
                    self.convertStatus = "Movie sent"
                    self.messageStatus = self.convertStatus
                    for step in steps {
                        self.appendMessageLog(step)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = false
                    self.convertStatus = "Movie send failed"
                    self.messageStatus = self.convertStatus
                    self.appendMessageLog("Movie send error: \(error)")
                }
            }
        }
    }

    private func sendProgressFrames(_ fills: [Double], durationSeconds: Int) {
        guard !isSending else { return }
        guard let port = UInt16(signPort) else {
            appendMessageLog("Invalid port: \(signPort)")
            return
        }

        let host = signIP
        let color = progressColor
        let showsPercent = progressShowsPercent
        let stopAfterOneCycle = progressStopAfterOneCycle
        let engine = progressSendEngine
        let selectedSpeed = speed
        let speedLabel = speed.label
        let speedCode = speed.sigmaCode
        let holdSeconds = max(0, pauseSeconds)
        let useEditorFontCompat = senderProfile == .editorFont
        let requestedFrameDelay = fills.count > 1 ? Double(durationSeconds) / Double(max(1, fills.count - 1)) : 0
        let transportFloorDelay = Self.progressTransportFloorSeconds(for: speed)
        let targetFrameDelay = fills.count > 1 ? max(requestedFrameDelay, transportFloorDelay) : 0
        let replayDisplayFloorDelay = fills.count > 1 && engine == .backgroundReplay
            ? Self.progressReplayDisplayFloorSeconds(for: speed)
            : 0
        let effectiveFrameDelay = max(targetFrameDelay, replayDisplayFloorDelay)

        if engine == .bitmapTemplate || engine == .bitmapRaw {
            progressStatus = "This bitmap engine is currently known-bad on this sign"
            messageStatus = progressStatus
            appendMessageLog("Progress blocked: \(engine.label) currently renders blank/I1 on this sign. Use Text (Stable), Bitmap Editor Program, or Bitmap Editor Generic.")
            return
        }

        isSending = true
        lastSendSucceeded = false
        progressStatus = fills.count > 1 ? "Running progress timer" : "Sending progress frame"
        messageStatus = progressStatus
        appendMessageLog("Progress: \(fills.count) frame(s), color=\(color.label), duration=\(durationSeconds)s, engine=\(engine.label)")

        Task.detached {
            do {
                var client = SigmaClient(host: host, port: port)
                var allSteps: [String] = []
                if engine == .backgroundReplay, fills.count > 1 {
                    allSteps.append("Background replay timer: stable stepped mode")
                    allSteps.append(String(format: "Requested cadence: %.2fs per frame", requestedFrameDelay))
                    allSteps.append(String(format: "Transport floor from speed %@: %.2fs per frame", speedLabel, transportFloorDelay))
                    allSteps.append(String(format: "Display floor for stable replay: %.2fs per frame", replayDisplayFloorDelay))
                    if requestedFrameDelay < transportFloorDelay {
                        allSteps.append(String(format: "Cadence clamped to %.2fs; requested %.2fs is faster than reliable transport", transportFloorDelay, requestedFrameDelay))
                    }
                    if effectiveFrameDelay > targetFrameDelay {
                        allSteps.append(String(format: "Replay cadence raised to %.2fs for visible frame stepping", effectiveFrameDelay))
                    }
                    if let sourceTiming = Self.backgroundReplaySequenceTimingHint() {
                        allSteps.append(
                            String(
                                format: "Sequence timing source: %@ code=0x%02X (%d)",
                                sourceTiming.source,
                                sourceTiming.code,
                                sourceTiming.code
                            )
                        )
                    }
                }

                if engine == .textFallback, fills.count > 1 {
                    let stepHoldSeconds = max(1, Int((requestedFrameDelay > 0 ? requestedFrameDelay : 1).rounded()))
                    allSteps.append("Text timer: single program send (firmware-side stepping)")
                    allSteps.append(String(format: "Step hold: %ds", stepHoldSeconds))
                    let options = SigmaTextOptions(
                        inEffectCode: UInt8(ascii: "1"),
                        outEffectCode: UInt8(ascii: "1"),
                        speedCode: speedCode,
                        horizontalAlignCode: UInt8(ascii: "0"),
                        verticalAligns: false,
                        holdSeconds: stepHoldSeconds,
                        wrapsText: false
                    )
                    let entries = fills.map { fill in
                        SigmaTextProgramEntry(
                            text: Self.progressTextLine(fill: fill, showsPercent: showsPercent),
                            font: .normal7,
                            color: color.sigmaColor,
                            options: options
                        )
                    }
                    allSteps.append("Program steps: \(entries.count)")
                    allSteps.append(contentsOf: try client.sendTextProgram(entries, editorFontCompat: useEditorFontCompat))
                    if stopAfterOneCycle {
                        let cycleSeconds = Double(entries.count) * Double(stepHoldSeconds)
                        allSteps.append(String(format: "Stop-after-cycle: scheduling static 100%% frame at +%.1fs", cycleSeconds))
                        if cycleSeconds > 0 {
                            try await Task.sleep(nanoseconds: UInt64(cycleSeconds * 1_000_000_000))
                        }
                        let stopOptions = SigmaTextOptions(
                            inEffectCode: UInt8(ascii: "1"),
                            outEffectCode: UInt8(ascii: "1"),
                            speedCode: speedCode,
                            horizontalAlignCode: UInt8(ascii: "0"),
                            verticalAligns: false,
                            holdSeconds: 9,
                            wrapsText: false
                        )
                        let finalLine = Self.progressTextLine(fill: 1.0, showsPercent: showsPercent)
                        allSteps.append(contentsOf: try client.sendText(
                            finalLine,
                            font: .normal7,
                            color: color.sigmaColor,
                            options: stopOptions,
                            editorFontCompat: useEditorFontCompat
                        ))
                    } else {
                        allSteps.append("Stop-after-cycle: disabled")
                    }

                    await MainActor.run {
                        self.isSending = false
                        self.lastSendSucceeded = true
                        self.progressStatus = "Progress program sent"
                        self.messageStatus = self.progressStatus
                        for step in allSteps {
                            self.appendMessageLog(step)
                        }
                    }
                    return
                }

                if engine == .backgroundReplay, fills.count > 1 {
                    let stepHoldSeconds = max(1, Int((requestedFrameDelay > 0 ? requestedFrameDelay : 1).rounded()))
                    let sequenceTimingCode = Self.rowChange120SequenceTimingCode() ?? UInt8(max(1, min(255, stepHoldSeconds)))
                    allSteps.append("Background replay timer: strict wire replay (known-good no-black)")
                    allSteps.append(String(format: "Step hold target: %ds", stepHoldSeconds))
                    allSteps.append(
                        String(
                            format: "Sequence timing code: 0x%02X (%d)%@",
                            sequenceTimingCode,
                            sequenceTimingCode,
                            Self.rowChange120SequenceTimingCode() != nil ? " (from row-change 120ms capture)" : ""
                        )
                    )
                    let templateFrames = max(2, Self.noBlackTemplateFrameCount() ?? 10)
                    let effectiveFills = Self.resampleFills(fills, to: templateFrames)
                    allSteps.append("Effective frames: \(templateFrames) (source: \(Self.preferredNoBlackSourceLabel() ?? "no-black template"))")
                    let replayBuild = try Self.makeNoBlackFirmwareProgressReplayPackets(
                        fills: effectiveFills,
                        color: color,
                        showsPercent: showsPercent,
                        speedCode: speedCode,
                        holdSeconds: stepHoldSeconds,
                        sequenceTimingCode: sequenceTimingCode,
                        stopAfterOneCycle: stopAfterOneCycle
                    )
                    allSteps.append("Background replay family: \(replayBuild.familyLabel)")
                    allSteps.append("Background replay packets: strict one-shot wire replay")
                    allSteps.append(contentsOf: try client.replayCapturedPackets(replayBuild.packets))
                    if stopAfterOneCycle, let finalFill = effectiveFills.last {
                        allSteps.append("Stop-after-cycle: embedded in sequence payload (no post-cycle latch)")
                        // Fallback latch only if the embedded one-cycle flag did not patch in.
                        if !replayBuild.familyLabel.contains("(one-cycle)") {
                            allSteps.append("Stop-after-cycle fallback: sequence patch unavailable; scheduling static final frame")
                        let observedStepSeconds = Self.noBlackObservedStepSeconds(for: selectedSpeed)
                        let startupDelaySeconds = Self.noBlackStartupDelaySeconds(for: selectedSpeed)
                        let observedCycleSeconds = startupDelaySeconds + Double(max(1, effectiveFills.count - 1)) * observedStepSeconds
                        let cycleSeconds = max(Double(max(1, durationSeconds)), observedCycleSeconds)
                        allSteps.append(
                            String(
                                format: "Stop-after-cycle: scheduling static final frame at +%.1fs (startup %.2fs + observed step %.2fs, requested %ds)",
                                cycleSeconds,
                                startupDelaySeconds,
                                observedStepSeconds,
                                durationSeconds
                            )
                        )
                        if cycleSeconds > 0 {
                            try await Task.sleep(nanoseconds: UInt64(cycleSeconds * 1_000_000_000))
                        }
                        let finalFrame = Self.progressFrame(fill: finalFill, color: color, showsPercent: showsPercent)
                        let baseLatchBuild = try Self.makeBackgroundReplayPackets(
                            pixels: finalFrame.pixels,
                            speedCode: speedCode,
                            holdSeconds: 9,
                            includeSetup: false
                        )
                        let latchBuild = Self.trimReplayForHotSwap(baseLatchBuild)
                        allSteps.append(contentsOf: try client.replayCapturedPackets(latchBuild.packets))
                        }
                    } else {
                        allSteps.append("Stop-after-cycle: disabled")
                    }

                    await MainActor.run {
                        self.isSending = false
                        self.lastSendSucceeded = true
                        self.progressStatus = "Progress program sent"
                        self.messageStatus = self.progressStatus
                        for step in allSteps {
                            self.appendMessageLog(step)
                        }
                    }
                    return
                }

                for (index, fill) in fills.enumerated() {
                    let frameStart = Date()
                    allSteps.append(String(format: "Progress %3.0f%%", fill * 100))
                    switch engine {
                    case .textFallback:
                        let line = Self.progressTextLine(fill: fill, showsPercent: showsPercent)
                        let options = SigmaTextOptions(
                            inEffectCode: UInt8(ascii: "1"),
                            outEffectCode: UInt8(ascii: "1"),
                            speedCode: speedCode,
                            horizontalAlignCode: UInt8(ascii: "0"),
                            verticalAligns: false,
                            holdSeconds: holdSeconds,
                            wrapsText: false
                        )
                        allSteps.append("Line: \(line)")
                        allSteps.append(contentsOf: try client.sendText(
                            line,
                            font: .normal7,
                            color: color.sigmaColor,
                            options: options,
                            editorFontCompat: useEditorFontCompat
                        ))
                    case .bitmapTemplate:
                        let frame = Self.progressFrame(fill: fill, color: color, showsPercent: showsPercent)
                        let nmg = Self.makePictureNmg(width: 80, height: 7, pixels: frame.pixels)
                        allSteps.append(contentsOf: try client.sendNmg(nmg, filename: "temp.Nmg", fileType: .text))
                    case .bitmapRaw:
                        let frame = Self.progressFrame(fill: fill, color: color, showsPercent: showsPercent)
                        let nmg = Self.makeRawPictureNmg(width: 80, height: 7, pixels: frame.pixels)
                        allSteps.append(contentsOf: try client.sendNmg(nmg, filename: "temp.Nmg", fileType: .text))
                    case .backgroundReplay:
                        let frame = Self.progressFrame(fill: fill, color: color, showsPercent: showsPercent)
                        let progressHold = fills.count > 1 ? 0 : holdSeconds
                        var replayBuild = try Self.makeBackgroundReplayPackets(
                            pixels: frame.pixels,
                            speedCode: speedCode,
                            holdSeconds: progressHold,
                            includeSetup: fills.count <= 1
                        )
                        if fills.count > 1 {
                            replayBuild = Self.trimReplayForHotSwap(replayBuild)
                        }
                        allSteps.append("Background replay family: \(replayBuild.familyLabel)")
                        if fills.count > 1 {
                            allSteps.append("Background replay packets: hot-swap chain (stable)")
                        } else {
                            allSteps.append("Background replay packets: full chain")
                        }
                        allSteps.append(contentsOf: try client.replayCapturedPackets(replayBuild.packets))
                    case .bitmapEditorProgram:
                        let frame = Self.progressFrame(fill: fill, color: color, showsPercent: showsPercent)
                        let nmg = Self.makeEditorTemplatePictureNmg(width: 80, height: 7, pixels: frame.pixels)
                        allSteps.append(contentsOf: try client.sendEditorProgramNmg(nmg, filename: "temp.Nmg"))
                    case .bitmapEditorGeneric:
                        let frame = Self.progressFrame(fill: fill, color: color, showsPercent: showsPercent)
                        let nmg = Self.makeEditorTemplatePictureNmg(width: 80, height: 7, pixels: frame.pixels)
                        // Pure Editor-compatible send path:
                        // no post-generation mutation and no resend loop.
                        allSteps.append(contentsOf: try client.sendEditorProgramNmg(nmg, filename: "temp.Nmg"))
                    }
                    let transportTime = Date().timeIntervalSince(frameStart)
                    allSteps.append(String(format: "Frame transport time: %.2fs", transportTime))
                    if index < fills.count - 1 && effectiveFrameDelay > 0 {
                        let remaining = max(0, effectiveFrameDelay - transportTime)
                        if remaining > 0 {
                            try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                        }
                    }
                }
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = true
                    self.progressStatus = fills.count > 1 ? "Progress complete" : "Progress frame sent"
                    self.messageStatus = self.progressStatus
                    for step in allSteps {
                        self.appendMessageLog(step)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = false
                    self.progressStatus = "Progress send failed"
                    self.messageStatus = "Progress send failed"
                    self.appendMessageLog("Progress error: \(error)")
                }
            }
        }
    }

    nonisolated private static func progressTextLine(fill: Double, showsPercent: Bool) -> String {
        let clamped = max(0, min(1, fill))
        let total = 16
        let filled = Int((clamped * Double(total)).rounded(.down))
        let bar = String(repeating: "#", count: filled) + String(repeating: "-", count: max(0, total - filled))
        if showsPercent {
            return String(format: "PROGRESS %3d%% [%@]", Int((clamped * 100).rounded()), bar)
        }
        return "PROGRESS [\(bar)]"
    }

    nonisolated private static func progressOverlayLine(fill: Double, showsPercent: Bool) -> String {
        let clamped = max(0, min(1, fill))
        let total = 10
        let filled = Int((clamped * Double(total)).rounded(.down))
        let solid = String(repeating: "{blk}", count: filled)
        let empty = String(repeating: " ", count: max(0, total - filled))
        let bar = solid + empty
        if showsPercent {
            return String(format: "%@ %3d%%", bar, Int((clamped * 100).rounded()))
        }
        return bar
    }

    private func graphicsBrushPixel() -> ProgressPixel {
        switch graphicsBrush {
        case .red: return .red
        case .green: return .green
        case .orange: return .orange
        case .erase: return .off
        }
    }

    nonisolated private static func pngTimestampString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    nonisolated private static func sanitizedFilenameStem(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(mapped).replacingOccurrences(of: "--", with: "-")
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-_")).isEmpty
            ? fallback
            : result
    }

    // FLW sequence rows are fixed-width (12 bytes) and behave best with DOS-style 8.3 names.
    // Keep movie sends deterministic so the extension is never truncated off the playlist row.
    nonisolated private static func makeSigma83MovieFilename(from rawName: String) -> String {
        let base = URL(fileURLWithPath: rawName).deletingPathExtension().lastPathComponent
        let stem = sanitizedFilenameStem(base, fallback: "MOVIE")
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        let short = String(stem.prefix(8))
        let finalStem = short.isEmpty ? "MOVIE" : short
        return "\(finalStem).FLW"
    }

    nonisolated private static func shouldSendCanvasLineAsBitmap(_ line: CanvasLinePayload, baseFont: AppFont, mode: MessageMode) -> Bool {
        guard mode == .fitted else { return false }
        if baseFont == .normal5 { return true }
        return line.styleRuns.contains { run in
            ["{font5}", "{font7}"].contains(run.token.lowercased())
        }
    }

    nonisolated private static func bitmapFrameForCanvasLine(
        _ line: CanvasLinePayload,
        baseFont: AppFont,
        baseColor: AppColor,
        basePalette: AppPalette
    ) -> ProgressFrame {
        let width = PixelFontRenderer.textWidth(line.rawText, baseStyle: baseFont, styleRuns: line.styleRuns)
        let xOffset = max(0, (80 - width) / 2)
        let rendered = PixelFontRenderer.render(
            text: line.rawText,
            baseStyle: baseFont,
            styleRuns: line.styleRuns,
            width: 80,
            height: 7,
            xOffset: xOffset
        )
        var pixels = Array(repeating: ProgressPixel.off, count: 80 * 7)
        for y in 0..<7 {
            for x in 0..<80 where rendered.pixels[y][x] {
                pixels[y * 80 + x] = progressPixel(
                    x: x,
                    y: y,
                    characterIndex: rendered.characterIndexes[y][x],
                    styleRuns: line.styleRuns,
                    baseColor: baseColor,
                    basePalette: basePalette
                )
            }
        }
        return ProgressFrame(pixels: pixels, renderedPixels: rendered)
    }

    nonisolated private static func bitmapFrameForCanvasLine(
        _ line: CanvasLinePayload,
        baseFont: AppFont,
        baseColor: AppColor,
        basePalette: AppPalette,
        xOffset: Int
    ) -> ProgressFrame {
        let rendered = PixelFontRenderer.render(
            text: line.rawText,
            baseStyle: baseFont,
            styleRuns: line.styleRuns,
            width: 80,
            height: 7,
            xOffset: xOffset
        )
        var pixels = Array(repeating: ProgressPixel.off, count: 80 * 7)
        for y in 0..<7 {
            for x in 0..<80 where rendered.pixels[y][x] {
                pixels[y * 80 + x] = progressPixel(
                    x: x,
                    y: y,
                    characterIndex: rendered.characterIndexes[y][x],
                    styleRuns: line.styleRuns,
                    baseColor: baseColor,
                    basePalette: basePalette
                )
            }
        }
        return ProgressFrame(pixels: pixels, renderedPixels: rendered)
    }

    nonisolated private static func progressPixel(
        x: Int,
        y: Int,
        characterIndex: Int?,
        styleRuns: [CanvasStyleRun],
        baseColor: AppColor,
        basePalette: AppPalette
    ) -> ProgressPixel {
        let token = styleRuns.last {
            guard let characterIndex else { return false }
            return characterIndex >= $0.location &&
            characterIndex < $0.location + $0.length &&
            !["{font5}", "{font7}"].contains($0.token.lowercased())
        }?.token.lowercased()

        switch token {
        case "{red}":
            return .red
        case "{green}":
            return .green
        case "{orange}", "{yellow}":
            return .orange
        case "{bands}":
            if y <= 1 { return .orange }
            if y <= 3 { return .green }
            return .red
        case "{characters}":
            return stripeProgressPixel(characterIndex ?? 0)
        case "{diagonal_down}":
            return stripeProgressPixel(x + y)
        case "{diagonal_up}":
            return stripeProgressPixel(x + (6 - y))
        default:
            switch basePalette {
            case .solid:
                return ProgressPixel(color: baseColor)
            case .horizontalBands:
                if y <= 1 { return .orange }
                if y <= 3 { return .green }
                return .red
            case .characterStripes:
                return stripeProgressPixel(characterIndex ?? 0)
            case .diagonalDown:
                return stripeProgressPixel(x + y)
            case .diagonalUp:
                return stripeProgressPixel(x + (6 - y))
            }
        }
    }

    nonisolated private static func overlayForegroundPixels(
        base: [ProgressPixel],
        foreground: [ProgressPixel]
    ) -> [ProgressPixel] {
        guard base.count == foreground.count else { return foreground }
        var merged = base
        for i in foreground.indices where foreground[i] != .off {
            merged[i] = foreground[i]
        }
        return merged
    }

    nonisolated private static func stripeProgressPixel(_ index: Int) -> ProgressPixel {
        switch index % 3 {
        case 0: return .red
        case 1: return .green
        default: return .orange
        }
    }

    nonisolated private static func progressFrame(fill: Double, color: AppColor, showsPercent: Bool) -> ProgressFrame {
        let clampedFill = max(0, min(1, fill))
        var pixels = Array(repeating: ProgressPixel.off, count: 80 * 7)

        func set(_ x: Int, _ y: Int, _ pixel: ProgressPixel) {
            guard x >= 0, x < 80, y >= 0, y < 7 else { return }
            pixels[y * 80 + x] = pixel
        }

        let active = ProgressPixel(color: color)
        let border = active
        for x in 0..<80 {
            set(x, 0, border)
            set(x, 6, border)
        }
        for y in 0..<7 {
            set(0, y, border)
            set(79, y, border)
        }

        let innerWidth = 76
        let filled = Int((Double(innerWidth) * clampedFill).rounded(.down))
        if filled > 0 {
            for y in 2...4 {
                for x in 2..<(2 + filled) {
                    set(x, y, active)
                }
            }
        }

        if showsPercent {
            let label = "\(Int((clampedFill * 100).rounded()))%"
            drawProgressText(label, into: &pixels)
        }

        let bools = (0..<7).map { y in
            (0..<80).map { x in pixels[y * 80 + x] != .off }
        }
        let indexes = Array(repeating: Array<Int?>(repeating: nil, count: 80), count: 7)
        return ProgressFrame(
            pixels: pixels,
            renderedPixels: PixelFontRenderer.RenderedPixels(pixels: bools, characterIndexes: indexes)
        )
    }

    nonisolated private static func drawProgressText(_ text: String, into pixels: inout [ProgressPixel]) {
        let glyphs = text.map { PixelFontRenderer.glyphRows(for: $0, style: .normal5) }
        let width = text.enumerated().reduce(0) { total, item in
            let glyph = glyphs[item.offset]
            return total + PixelFontRenderer.advance(for: item.element, glyph: glyph, style: .normal5)
        } - 1
        var cursor = max(2, (80 - width) / 2)
        for (character, glyph) in zip(text, glyphs) {
            let yOffset = 1
            for (gy, row) in glyph.enumerated() {
                for (gx, bit) in row.enumerated() where bit == "1" {
                    let x = cursor + gx
                    let y = yOffset + gy
                    if x >= 0, x < 80, y >= 0, y < 7 {
                        pixels[y * 80 + x] = .orange
                    }
                }
            }
            cursor += PixelFontRenderer.advance(for: character, glyph: glyph, style: .normal5)
        }
    }

    nonisolated private static func makePictureNmg(width: Int, height: Int, pixels: [ProgressPixel]) -> Data {
        let bmp = makeRGB565BMP(width: width, height: height, pixels: pixels)
        if let template = lightPictureTemplateNmg,
           let replaced = replaceBmp(inTemplateNmg: template, with: bmp) {
            return replaced
        }
        return makeRawPictureNmg(width: width, height: height, pixels: pixels)
    }

    nonisolated private static func makeRawPictureNmg(width: Int, height: Int, pixels: [ProgressPixel]) -> Data {
        let bmp = makeRGB565BMP(width: width, height: height, pixels: pixels)
        var nmg = Data([
            0x01, 0x5a, 0x30, 0x30, 0x02, 0x41, 0x0a, 0x49,
            0x31, 0x0a, 0x4f, 0x31, 0x0e, 0x32, 0x30, 0x30,
            0x30, 0x32, 0x14, 0x40, 0x30, 0x04, 0x52, 0x43,
            0x01, 0x00, 0x01, 0x30
        ])
        nmg.appendLE32(UInt32(bmp.count))
        nmg.appendLE32(0x28)
        nmg.append(contentsOf: repeatElement(UInt8(0), count: max(0, 63 - nmg.count)))
        nmg.append(bmp)
        return nmg
    }

    nonisolated private static func makeEditorTemplatePictureNmg(width: Int, height: Int, pixels: [ProgressPixel]) -> Data {
        let bmp = makeRGB565BMP(width: width, height: height, pixels: pixels)
        if let template = editorProgramTemplateNmg,
           let replaced = replaceAllBmps(inTemplateNmg: template, with: bmp, trimAfterFirstBmp: false) {
            return replaced
        }
        return makeRawPictureNmg(width: width, height: height, pixels: pixels)
    }

    nonisolated private static let lightPictureTemplateNmg: Data? = {
        let candidates = [
            Paths.demoDirectory.appendingPathComponent("chevron-80x7-generated.nmg").path(),
            Paths.demoDirectory.appendingPathComponent("chevron-80x7-showbmp-24.nmg").path()
        ]
        for path in candidates {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                return data
            }
        }
        return nil
    }()

    nonisolated private static let editorProgramTemplateNmg: Data? = {
        let path = Paths.editorNmg.path()
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }()

    private struct EditorTemplatePair: Sendable {
        let nmg: Data
        let sequence: Data
        let payloadLength: Int?
        let sourceLabel: String
    }

    private enum ReplayPatchError: Error, CustomStringConvertible {
        case replayTemplateMissing
        case noFileChunkPackets
        case chunkCountMismatch(expected: Int, got: Int)
        case commitPacketMissing

        var description: String {
            switch self {
            case .replayTemplateMissing:
                return "No captured replay/template available"
            case .noFileChunkPackets:
                return "Replay template did not contain file chunk packets"
            case .chunkCountMismatch(let expected, let got):
                return "Replay chunk count mismatch: expected \(expected), got \(got)"
            case .commitPacketMissing:
                return "Replay template did not contain commit packet"
            }
        }
    }

    private struct BackgroundReplayBuild: Sendable {
        let packets: [SigmaReplayPacket]
        let familyLabel: String
    }

    private struct BackgroundReplayProgramBuild: Sendable {
        let entries: [SigmaBinaryProgramEntry]
        let familyLabel: String
    }

    private struct ForegroundOverlayReplayBuild: Sendable {
        let build: BackgroundReplayBuild
        let frameCount: Int
        let debugLines: [String]
    }

    nonisolated private static func makeBackgroundReplayPackets(
        pixels: [ProgressPixel],
        speedCode: UInt8,
        holdSeconds: Int,
        includeSetup: Bool = true
    ) throws -> BackgroundReplayBuild {
        guard let family = loadBackgroundReplayFamilyForProgress()
        else {
            throw ReplayPatchError.replayTemplateMissing
        }
        var replay = family.replayPackets
        let templatePair = family.templatePair

        let bmp = makeRGB565BMP(width: 80, height: 7, pixels: pixels)
        let patchedProgram = replaceAllBmps(
            inTemplateNmg: templatePair.nmg,
            with: bmp,
            trimAfterFirstBmp: false
        ) ?? templatePair.nmg

        let payloadLength = max(1, min(templatePair.payloadLength ?? patchedProgram.count, patchedProgram.count))
        var content = Data(patchedProgram.prefix(payloadLength))
        content = forceStaticBitmapPlayback(in: content)
        content = applyProgramTimingControls(
            in: content,
            speedCode: speedCode,
            holdSeconds: holdSeconds
        )
        let chunks = content.chunked(maxSize: 768)

        let fileChunkIndexes = replay.enumerated().compactMap { index, packet -> Int? in
            guard packet.payload.count >= 24 else { return nil }
            if let command = replayCommand(packet.payload), command == (0x02, 0x04) {
                return index
            }
            return nil
        }
        guard !fileChunkIndexes.isEmpty else { throw ReplayPatchError.noFileChunkPackets }
        guard fileChunkIndexes.count == chunks.count else {
            throw ReplayPatchError.chunkCountMismatch(expected: chunks.count, got: fileChunkIndexes.count)
        }

        for (chunkIdx, packetIndex) in fileChunkIndexes.enumerated() {
            var payload = replay[packetIndex].payload
            let chunk = chunks[chunkIdx]
            guard payload.count >= 24 else { continue }

            let descriptorWords = Int(payload.le16(at: 14))
            let descriptorStart = 16
            let descriptorLength = descriptorWords * 4
            let chunkStart = descriptorStart + descriptorLength
            let oldChunkLength = Int(payload.le32(at: 4))
            let oldChunkEnd = chunkStart + oldChunkLength
            guard chunkStart <= payload.count, oldChunkEnd <= payload.count else { continue }

            payload.setLE32(UInt32(chunk.count), at: 4)
            payload.setLE32(UInt32(content.count), at: descriptorStart + 14)
            payload.setLE16(768, at: descriptorStart + 18)
            payload.setLE16(UInt16(chunks.count), at: descriptorStart + 20)
            payload.setLE16(UInt16(chunkIdx + 1), at: descriptorStart + 22)
            payload.replaceSubrange(chunkStart..<oldChunkEnd, with: chunk)
            payload.rewriteSigmaFrameCRC()
            replay[packetIndex] = SigmaReplayPacket(
                delayMilliseconds: replay[packetIndex].delayMilliseconds,
                sourcePort: replay[packetIndex].sourcePort,
                payload: payload
            )
        }

        guard let commitIndex = replay.firstIndex(where: { packet in
            if let command = replayCommand(packet.payload) {
                return command == (0x02, 0x0e)
            }
            return false
        }) else {
            throw ReplayPatchError.commitPacketMissing
        }
        var commit = replay[commitIndex].payload
        let commitBody = 16
        guard commit.count >= commitBody + 40 else {
            throw ReplayPatchError.commitPacketMissing
        }
        commit.setLE32(UInt32(content.count), at: commitBody + 32)
        commit.setLE32(UInt32(sigmaX25(content)), at: commitBody + 36)
        commit.rewriteSigmaFrameCRC()
        replay[commitIndex] = SigmaReplayPacket(
            delayMilliseconds: replay[commitIndex].delayMilliseconds,
            sourcePort: replay[commitIndex].sourcePort,
            payload: commit
        )

        let sequenceTimingCode = UInt8(max(0, min(255, holdSeconds)))
        replay = replay.map { packet in
            guard let command = replayCommand(packet.payload), command == (0x02, 0x02) else {
                return packet
            }
            let patchedPayload = patchSequenceTimingCode(in: packet.payload, timingCode: sequenceTimingCode)
            return SigmaReplayPacket(
                delayMilliseconds: packet.delayMilliseconds,
                sourcePort: packet.sourcePort,
                payload: patchedPayload
            )
        }

        if !includeSetup {
            if let firstChunkIndex = replay.firstIndex(where: { packet in
                if let command = replayCommand(packet.payload) {
                    return command == (0x02, 0x04)
                }
                return false
            }), firstChunkIndex > 0 {
                replay = Array(replay[firstChunkIndex...])
            }
        }

        return BackgroundReplayBuild(packets: replay, familyLabel: family.label)
    }

    nonisolated private static func trimReplayForHotSwap(_ build: BackgroundReplayBuild) -> BackgroundReplayBuild {
        // Keep chunk upload + commit + replay trigger.
        // Drop only SEQUENT.SYS resend, so each frame still receives a lightweight
        // 04:02 play command and actually advances on the sign.
        var output: [SigmaReplayPacket] = []
        for packet in build.packets {
            guard let command = replayCommand(packet.payload) else {
                output.append(packet)
                continue
            }
            if command == (0x02, 0x02) {
                continue // send SEQUENT.SYS
            }
            if command == (0x04, 0x02) {
                // Avoid baked replay wait from capture for hot-swap updates.
                output.append(
                    SigmaReplayPacket(
                        delayMilliseconds: 0,
                        sourcePort: packet.sourcePort,
                        payload: packet.payload
                    )
                )
                continue
            }
            let normalizedDelay: Int
            if command == (0x02, 0x0e) {
                normalizedDelay = min(packet.delayMilliseconds, 40)
            } else if command == (0x02, 0x04) {
                normalizedDelay = min(packet.delayMilliseconds, 15)
            } else {
                normalizedDelay = min(packet.delayMilliseconds, 20)
            }
            output.append(
                SigmaReplayPacket(
                    delayMilliseconds: normalizedDelay,
                    sourcePort: packet.sourcePort,
                    payload: packet.payload
                )
            )
        }
        return BackgroundReplayBuild(packets: output, familyLabel: build.familyLabel)
    }

    nonisolated private static func normalizeReplayDelaysForProgressStart(_ build: BackgroundReplayBuild) -> BackgroundReplayBuild {
        let normalized = build.packets.map { packet in
            guard let command = replayCommand(packet.payload) else {
                return SigmaReplayPacket(
                    delayMilliseconds: min(packet.delayMilliseconds, 40),
                    sourcePort: packet.sourcePort,
                    payload: packet.payload
                )
            }

            let delay: Int
            switch command {
            case (0x04, 0x01):
                delay = min(packet.delayMilliseconds, 30)
            case (0x02, 0x04):
                delay = min(packet.delayMilliseconds, 20)
            case (0x02, 0x0e):
                delay = min(packet.delayMilliseconds, 80)
            case (0x02, 0x02):
                delay = min(packet.delayMilliseconds, 80)
            case (0x04, 0x02):
                delay = min(packet.delayMilliseconds, 20)
            default:
                delay = min(packet.delayMilliseconds, 40)
            }

            return SigmaReplayPacket(
                delayMilliseconds: delay,
                sourcePort: packet.sourcePort,
                payload: packet.payload
            )
        }
        return BackgroundReplayBuild(packets: normalized, familyLabel: build.familyLabel)
    }

    nonisolated private static func makeBackgroundReplayProgramEntries(
        fills: [Double],
        color: AppColor,
        showsPercent: Bool,
        speedCode: UInt8,
        holdSeconds: Int
    ) throws -> BackgroundReplayProgramBuild {
        guard let family = loadBackgroundReplayFamilyForProgress() else {
            throw ReplayPatchError.replayTemplateMissing
        }

        var entries: [SigmaBinaryProgramEntry] = []
        for (index, fill) in fills.enumerated() {
            let frame = progressFrame(fill: fill, color: color, showsPercent: showsPercent)
            let bmp = makeRGB565BMP(width: 80, height: 7, pixels: frame.pixels)
            let patchedProgram = replaceAllBmps(
                inTemplateNmg: family.templatePair.nmg,
                with: bmp,
                trimAfterFirstBmp: false
            ) ?? family.templatePair.nmg

            var content = Data(
                patchedProgram.prefix(
                    max(
                        1,
                        min(family.templatePair.payloadLength ?? patchedProgram.count, patchedProgram.count)
                    )
                )
            )
            content = forceStaticBitmapPlayback(in: content)
            content = applyProgramTimingControls(
                in: content,
                speedCode: speedCode,
                holdSeconds: holdSeconds
            )

            let payloadLength = max(
                1,
                min(family.templatePair.payloadLength ?? content.count, content.count)
            )
            let filename = String(format: "PRG%03d.Nmg", index + 1)
            entries.append(
                SigmaBinaryProgramEntry(
                    filename: filename,
                    content: content,
                    fileType: .text,
                    payloadLengthOverride: payloadLength
                )
            )
        }

        return BackgroundReplayProgramBuild(entries: entries, familyLabel: family.label)
    }

    nonisolated private static func loadEditorProgressProgramTemplatePair() -> EditorTemplatePair? {
        let nmgPath = Paths.capturesDirectory.appendingPathComponent("editor-progress-20260503-022039/temp.Nmg.after").path()
        let seqPath = Paths.capturesDirectory.appendingPathComponent("editor-progress-20260503-022039/SequentList.tmps.after").path()
        guard let nmg = try? Data(contentsOf: URL(fileURLWithPath: nmgPath)),
              let seq = try? Data(contentsOf: URL(fileURLWithPath: seqPath)),
              !nmg.isEmpty,
              !seq.isEmpty
        else {
            return nil
        }
        let payloadLength = sequencePayloadLength(for: "temp.Nmg", in: seq)
        return EditorTemplatePair(
            nmg: nmg,
            sequence: seq,
            payloadLength: payloadLength,
            sourceLabel: "editor progress capture 022039"
        )
    }

    nonisolated private static func loadEditorNoBlackStudyTemplatePair() -> EditorTemplatePair? {
        let nmgPath = Paths.capturesDirectory.appendingPathComponent("editor-no-black-study-20260503-025048/temp.Nmg.after").path()
        let seqPath = Paths.capturesDirectory.appendingPathComponent("editor-no-black-study-20260503-025048/SequentList.tmps.after").path()
        guard let nmg = try? Data(contentsOf: URL(fileURLWithPath: nmgPath)),
              let seq = try? Data(contentsOf: URL(fileURLWithPath: seqPath)),
              !nmg.isEmpty,
              !seq.isEmpty
        else {
            return nil
        }
        let payloadLength = sequencePayloadLength(for: "temp.Nmg", in: seq)
        return EditorTemplatePair(
            nmg: nmg,
            sequence: seq,
            payloadLength: payloadLength,
            sourceLabel: "editor no-black study 025048"
        )
    }

    nonisolated private static func loadEditorRowChange120TemplatePair() -> EditorTemplatePair? {
        let nmgPath = Paths.capturesDirectory.appendingPathComponent("editor-row-change-120ms-20260504-184709/from-sigma-1848/temp.Nmg").path()
        let seqPath = Paths.capturesDirectory.appendingPathComponent("editor-row-change-120ms-20260504-184709/from-sigma-1848/SequentList.tmps").path()
        guard let nmg = try? Data(contentsOf: URL(fileURLWithPath: nmgPath)),
              let seq = try? Data(contentsOf: URL(fileURLWithPath: seqPath)),
              !nmg.isEmpty,
              !seq.isEmpty
        else {
            return nil
        }
        // This capture is proven live on-sign, but sequence length markers are not
        // reliable for our mutation path, so keep full payload.
        return EditorTemplatePair(
            nmg: nmg,
            sequence: seq,
            payloadLength: nil,
            sourceLabel: "editor row-change 120ms 184709"
        )
    }

    nonisolated private static func loadLiveEditorNoBlackTemplatePair() -> EditorTemplatePair? {
        let nmgPath = Paths.editorNmg.path()
        let seqPath = Paths.editorSequence.path()
        guard let nmg = try? Data(contentsOf: URL(fileURLWithPath: nmgPath)),
              let seq = try? Data(contentsOf: URL(fileURLWithPath: seqPath)),
              !nmg.isEmpty,
              !seq.isEmpty
        else {
            return nil
        }
        // Live captures can carry stale/short payload markers in SequentList.tmps.
        // For the active Editor path, trust the full NMG size.
        let payloadLength: Int? = nil
        return EditorTemplatePair(
            nmg: nmg,
            sequence: seq,
            payloadLength: payloadLength,
            sourceLabel: "live editor capture (sigma3000_extracted)"
        )
    }

    nonisolated private static func loadPreferredNoBlackTemplatePair() -> EditorTemplatePair? {
        // Preferred default: captured 120ms row-change family (fast, proven live).
        let rowChange120 = loadEditorRowChange120TemplatePair()
        if let rowChange120 {
            return rowChange120
        }
        let study = loadEditorNoBlackStudyTemplatePair()
        if let study {
            return study
        }
        return loadLiveEditorNoBlackTemplatePair()
    }

    nonisolated private static func preferredNoBlackSourceLabel() -> String? {
        loadPreferredNoBlackTemplatePair()?.sourceLabel
    }

    nonisolated private static func makeNoBlackStudyProgressProgramNmg(template: Data, fills: [Double]) -> Data {
        // Captured placeholder words in this template are fixed-width slots:
        // ONE, TWO, THREE, FOUR, FIVE, SIX, SEVEN, EIGHT, NINE, TEN
        // Replace them with fixed-width ASCII bars so file length/structure stays stable.
        let slots: [(word: String, width: Int)] = [
            ("ONE", 3), ("TWO", 3), ("THREE", 5), ("FOUR", 4), ("FIVE", 4),
            ("SIX", 3), ("SEVEN", 5), ("EIGHT", 5), ("NINE", 4), ("TEN", 3)
        ]
        let levels = resampleFills(fills, to: slots.count)
        var output = template
        for (index, slot) in slots.enumerated() {
            guard let range = output.firstRange(of: Data(slot.word.utf8)) else { continue }
            let fill = max(0, min(1, levels[index]))
            let filled = Int((Double(slot.width) * fill).rounded(.down))
            let bar = String(repeating: "|", count: filled)
                + String(repeating: " ", count: max(0, slot.width - filled))
            output.replaceSubrange(range, with: Data(bar.utf8))
        }
        return output
    }

    nonisolated private static func scrubNoBlackTemplateLabels(in template: Data) -> Data {
        // The no-black capture embeds placeholder row labels in ASCII:
        // ONE..TEN. Remove them so they never leak to the sign.
        let slots: [(word: String, width: Int)] = [
            ("ONE", 3), ("TWO", 3), ("THREE", 5), ("FOUR", 4), ("FIVE", 4),
            ("SIX", 3), ("SEVEN", 5), ("EIGHT", 5), ("NINE", 4), ("TEN", 3)
        ]
        var output = template
        for slot in slots {
            guard let range = output.firstRange(of: Data(slot.word.utf8)) else { continue }
            output.replaceSubrange(range, with: Data(repeating: 0x20, count: slot.width))
        }
        return output
    }

    nonisolated private static func makeProgressProgramNmg(
        template: Data,
        fills: [Double],
        color: AppColor,
        showsPercent: Bool
    ) throws -> Data {
        let bmpOffsets = findBmpOffsets(in: template)
        guard !bmpOffsets.isEmpty else {
            throw ReplayPatchError.replayTemplateMissing
        }

        let targetFills = resampleFills(fills, to: bmpOffsets.count)
        let bmps: [Data] = targetFills.map { fill in
            let frame = progressFrame(fill: fill, color: color, showsPercent: showsPercent)
            return makeRGB565BMP(width: 80, height: 7, pixels: frame.pixels)
        }
        return replaceBmpPixelDataAtOffsets(in: template, offsets: bmpOffsets, bmps: bmps)
    }

    nonisolated private static func resampleFills(_ fills: [Double], to count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard !fills.isEmpty else { return Array(repeating: 0, count: count) }
        if fills.count == count { return fills }
        if fills.count == 1 { return Array(repeating: fills[0], count: count) }
        if count == 1 { return [fills.last ?? 0] }

        var result: [Double] = []
        result.reserveCapacity(count)
        let sourceLast = Double(fills.count - 1)
        for index in 0..<count {
            let t = Double(index) / Double(count - 1)
            let pos = t * sourceLast
            let lo = Int(floor(pos))
            let hi = min(fills.count - 1, lo + 1)
            let frac = pos - Double(lo)
            let value = fills[lo] * (1 - frac) + fills[hi] * frac
            result.append(max(0, min(1, value)))
        }
        return result
    }

    nonisolated private static func findBmpOffsets(in data: Data) -> [Int] {
        var offsets: [Int] = []
        var offset = 0
        while offset + 18 < data.count {
            guard let marker = data[offset...].firstRange(of: Data([0x42, 0x4d])) else { break }
            let bmOffset = marker.lowerBound
            if isLikelyBmpHeader(data, at: bmOffset) {
                offsets.append(bmOffset)
                let bmpSize = Int(data.le32(at: bmOffset + 2))
                if bmpSize > 0 {
                    offset = bmOffset + bmpSize
                    continue
                }
            }
            offset = bmOffset + 2
        }
        return offsets
    }

    nonisolated private static func replaceBmpPixelDataAtOffsets(
        in template: Data,
        offsets: [Int],
        bmps: [Data]
    ) -> Data {
        guard offsets.count == bmps.count else { return template }
        var data = template
        for (index, offset) in offsets.enumerated() {
            let bmp = bmps[index]
            let templateFileSize = Int(data.le32(at: offset + 2))
            let templatePixelOffset = Int(data.le32(at: offset + 10))
            let templateImageSize = Int(data.le32(at: offset + 34))
            let bmpPixelOffset = Int(bmp.le32(at: 10))
            let bmpImageSize = Int(bmp.le32(at: 34))

            guard templateFileSize > 0,
                  templatePixelOffset > 0,
                  templateImageSize > 0,
                  bmpPixelOffset > 0,
                  bmpImageSize > 0 else {
                continue
            }

            let templatePixelStart = offset + templatePixelOffset
            let templatePixelEnd = templatePixelStart + templateImageSize
            let bmpPixelStart = bmpPixelOffset
            let bmpPixelEnd = bmpPixelStart + bmpImageSize
            guard templatePixelEnd <= data.count, bmpPixelEnd <= bmp.count else { continue }

            let count = min(templateImageSize, bmpImageSize)
            data.replaceSubrange(
                templatePixelStart..<(templatePixelStart + count),
                with: bmp[bmpPixelStart..<(bmpPixelStart + count)]
            )
        }
        return data
    }

    nonisolated private static func cloneFirstBmpFrameAcrossTemplate(_ template: Data) -> Data {
        let offsets = findBmpOffsets(in: template)
        guard offsets.count > 1 else { return template }
        let firstOffset = offsets[0]
        let firstPixelOffset = Int(template.le32(at: firstOffset + 10))
        let firstImageSize = Int(template.le32(at: firstOffset + 34))
        guard firstPixelOffset > 0, firstImageSize > 0 else { return template }
        let firstPixelStart = firstOffset + firstPixelOffset
        let firstPixelEnd = firstPixelStart + firstImageSize
        guard firstPixelEnd <= template.count else { return template }
        let firstPixelData = template[firstPixelStart..<firstPixelEnd]

        var data = template
        for offset in offsets.dropFirst() {
            let pixelOffset = Int(data.le32(at: offset + 10))
            let imageSize = Int(data.le32(at: offset + 34))
            guard pixelOffset > 0, imageSize > 0 else { continue }
            let pixelStart = offset + pixelOffset
            let pixelEnd = pixelStart + imageSize
            guard pixelEnd <= data.count else { continue }
            let copyCount = min(imageSize, firstPixelData.count)
            data.replaceSubrange(
                pixelStart..<(pixelStart + copyCount),
                with: firstPixelData.prefix(copyCount)
            )
        }
        return data
    }

    nonisolated private static func replayCommand(_ packet: Data) -> (UInt8, UInt8)? {
        guard packet.count >= 14 else { return nil }
        return (packet[12], packet[13])
    }

    nonisolated private static func patchSequenceTimingCode(in payload: Data, timingCode: UInt8) -> Data {
        var patched = payload
        var i = 0
        while i + 3 < patched.count {
            if patched[i] == 0x26, patched[i + 1] == 0x20, patched[i + 2] == 0x05 {
                patched[i + 3] = timingCode
            }
            i += 1
        }
        patched.rewriteSigmaFrameCRC()
        return patched
    }

    nonisolated private static func patchSequenceStopAfterCycle(in payload: Data) -> (data: Data, patchedCount: Int) {
        var patched = payload
        var patchedCount = 0
        var i = 0
        // Pattern seen in captures: 26 20 05 <timing> 01 01 01 <loopFlag>
        // We set <loopFlag> to 00 so firmware should stop after one cycle.
        while i + 7 < patched.count {
            if patched[i] == 0x26,
               patched[i + 1] == 0x20,
               patched[i + 2] == 0x05,
               patched[i + 4] == 0x01,
               patched[i + 5] == 0x01,
               patched[i + 6] == 0x01 {
                if patched[i + 7] == 0x01 {
                    patched[i + 7] = 0x00
                    patchedCount += 1
                }
                i += 8
                continue
            }
            i += 1
        }
        if patchedCount > 0 {
            patched.rewriteSigmaFrameCRC()
        }
        return (patched, patchedCount)
    }

    nonisolated private static func sequenceTimingCode(in sequence: Data) -> UInt8? {
        var i = 0
        while i + 3 < sequence.count {
            if sequence[i] == 0x26, sequence[i + 1] == 0x20, sequence[i + 2] == 0x05 {
                return sequence[i + 3]
            }
            i += 1
        }
        return nil
    }

    nonisolated private static func rowChange120SequenceTimingCode() -> UInt8? {
        let seqPath = Paths.capturesDirectory.appendingPathComponent("editor-row-change-120ms-20260504-184709/from-sigma-1848/SequentList.tmps").path()
        guard let seq = try? Data(contentsOf: URL(fileURLWithPath: seqPath)), !seq.isEmpty else {
            return nil
        }
        return sequenceTimingCode(in: seq)
    }

    nonisolated private static func loadCapturedBackgroundReplayPackets() -> [SigmaReplayPacket]? {
        let fm = FileManager.default
        let capturesRoot = Paths.capturesDirectory
        let preferred = (try? fm.contentsOfDirectory(
            at: capturesRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?
            .filter { $0.lastPathComponent.hasPrefix("backimage-clean-wire-") && $0.pathExtension == "tsv" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first

        let fallback = URL(fileURLWithPath: Paths.capturesDirectory.appendingPathComponent("backimage-wire-20260503-013223.replay.tsv").path())
        let source = preferred ?? fallback
        guard let raw = try? String(contentsOf: source, encoding: .utf8) else { return nil }
        var packets: [SigmaReplayPacket] = []
        for line in raw.split(whereSeparator: \.isNewline) {
            let text = String(line)
            if text.isEmpty || text.hasPrefix("#") { continue }
            let parts = text.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            guard let delay = Int(parts[0]), let sourcePort = UInt16(parts[1]) else { continue }
            let hex = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let payload = Data(hexString: hex), !payload.isEmpty else { continue }
            packets.append(SigmaReplayPacket(delayMilliseconds: delay, sourcePort: sourcePort, payload: payload))
        }
        return packets.isEmpty ? nil : packets
    }

    nonisolated private static func loadEditorProgressReplayPackets() -> [SigmaReplayPacket]? {
        let path = Paths.capturesDirectory.appendingPathComponent("editor-progress-20260503-022039/wire.replay.tsv").path()
        return loadReplayPacketsFromTSV(path)
    }

    nonisolated private static func loadEditorNoBlackStudyReplayPackets() -> [SigmaReplayPacket]? {
        let path = Paths.capturesDirectory.appendingPathComponent("editor-no-black-study-20260503-025048/wire.replay.tsv").path()
        return loadReplayPacketsFromTSV(path)
    }

    nonisolated private static func loadEditorRowChange120ReplayPackets() -> [SigmaReplayPacket]? {
        let path = Paths.capturesDirectory.appendingPathComponent("editor-row-change-120ms-20260504-184709/editor-120ms-live-wire-2.replay.tsv").path()
        return loadReplayPacketsFromTSV(path)
    }

    nonisolated private static func loadPreferredNoBlackReplayPackets() -> (packets: [SigmaReplayPacket], label: String)? {
        if let packets = loadEditorRowChange120ReplayPackets() {
            return (packets, "editor row-change 120ms 184709")
        }
        if let packets = loadEditorNoBlackStudyReplayPackets() {
            return (packets, "editor no-black study 025048")
        }
        return nil
    }

    nonisolated private static func makeNoBlackProgressReplayPackets(
        _ packets: [SigmaReplayPacket],
        fills: [Double],
        showsPercent _: Bool
    ) -> [SigmaReplayPacket] {
        var output = packets
        let slots: [(word: String, width: Int)] = [
            ("ONE", 3), ("TWO", 3), ("THREE", 5), ("FOUR", 4), ("FIVE", 4),
            ("SIX", 3), ("SEVEN", 5), ("EIGHT", 5), ("NINE", 4), ("TEN", 3)
        ]
        let placeholders = ["ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN"]
        let levels = resampleFills(fills, to: slots.count)
        for (index, slot) in slots.enumerated() {
            let fill = max(0, min(1, levels[index]))
            let filled = Int((10.0 * fill).rounded(.down))
            let bar10 = String(repeating: "X", count: filled)
                + String(repeating: ".", count: max(0, 10 - filled))
            output = replaceFirstAsciiTokenInReplayPackets(output, from: placeholders[index], to: bar10.prefix(slot.width).description)
        }
        return output
    }

    nonisolated private static func makeNoBlackFirmwareProgressReplayPackets(
        fills: [Double],
        color: AppColor,
        showsPercent: Bool,
        speedCode: UInt8,
        holdSeconds: Int,
        sequenceTimingCode: UInt8,
        stopAfterOneCycle: Bool
    ) throws -> BackgroundReplayBuild {
        guard let replayFamily = loadPreferredNoBlackReplayPackets(),
              let templatePair = loadPreferredNoBlackTemplatePair()
        else {
            throw ReplayPatchError.replayTemplateMissing
        }

        var replay = replayFamily.packets
        var content = try makeProgressProgramNmg(
            template: templatePair.nmg,
            fills: fills,
            color: color,
            showsPercent: showsPercent
        )
        content = scrubNoBlackTemplateLabels(in: content)
        content = forceStaticBitmapPlayback(in: content)
        content = applyProgramTimingControls(
            in: content,
            speedCode: speedCode,
            holdSeconds: holdSeconds
        )

        let payloadLength = max(1, min(templatePair.payloadLength ?? content.count, content.count))
        content = Data(content.prefix(payloadLength))
        let chunks = content.chunked(maxSize: 768)

        let fileChunkIndexes = replay.enumerated().compactMap { index, packet -> Int? in
            guard packet.payload.count >= 24 else { return nil }
            if let command = replayCommand(packet.payload), command == (0x02, 0x04) {
                return index
            }
            return nil
        }
        guard !fileChunkIndexes.isEmpty else { throw ReplayPatchError.noFileChunkPackets }
        guard fileChunkIndexes.count == chunks.count else {
            throw ReplayPatchError.chunkCountMismatch(expected: chunks.count, got: fileChunkIndexes.count)
        }

        for (chunkIdx, packetIndex) in fileChunkIndexes.enumerated() {
            var payload = replay[packetIndex].payload
            let chunk = chunks[chunkIdx]
            guard payload.count >= 24 else { continue }

            let descriptorWords = Int(payload.le16(at: 14))
            let descriptorStart = 16
            let descriptorLength = descriptorWords * 4
            let chunkStart = descriptorStart + descriptorLength
            let oldChunkLength = Int(payload.le32(at: 4))
            let oldChunkEnd = chunkStart + oldChunkLength
            guard chunkStart <= payload.count, oldChunkEnd <= payload.count else { continue }

            payload.setLE32(UInt32(chunk.count), at: 4)
            payload.setLE32(UInt32(content.count), at: descriptorStart + 14)
            payload.setLE16(768, at: descriptorStart + 18)
            payload.setLE16(UInt16(chunks.count), at: descriptorStart + 20)
            payload.setLE16(UInt16(chunkIdx + 1), at: descriptorStart + 22)
            payload.replaceSubrange(chunkStart..<oldChunkEnd, with: chunk)
            payload.rewriteSigmaFrameCRC()

            replay[packetIndex] = SigmaReplayPacket(
                delayMilliseconds: replay[packetIndex].delayMilliseconds,
                sourcePort: replay[packetIndex].sourcePort,
                payload: payload
            )
        }

        var patchedCommit = false
        for idx in replay.indices {
            guard let command = replayCommand(replay[idx].payload), command == (0x02, 0x0e) else {
                continue
            }
            var commit = replay[idx].payload
            let commitBody = 16
            guard commit.count >= commitBody + 40 else { continue }

            commit.setLE32(UInt32(content.count), at: commitBody + 32)
            commit.setLE32(UInt32(sigmaX25(content)), at: commitBody + 36)
            commit.rewriteSigmaFrameCRC()
            replay[idx] = SigmaReplayPacket(
                delayMilliseconds: replay[idx].delayMilliseconds,
                sourcePort: replay[idx].sourcePort,
                payload: commit
            )
            patchedCommit = true
        }

        guard patchedCommit else { throw ReplayPatchError.commitPacketMissing }

        var stopPatchCount = 0
        replay = replay.map { packet in
            guard let command = replayCommand(packet.payload), command == (0x02, 0x02) else {
                return packet
            }
            var patchedPayload = patchSequenceTimingCode(in: packet.payload, timingCode: sequenceTimingCode)
            if stopAfterOneCycle {
                let stopPatch = patchSequenceStopAfterCycle(in: patchedPayload)
                patchedPayload = stopPatch.data
                stopPatchCount += stopPatch.patchedCount
            }
            return SigmaReplayPacket(
                delayMilliseconds: packet.delayMilliseconds,
                sourcePort: packet.sourcePort,
                payload: patchedPayload
            )
        }

        return BackgroundReplayBuild(
            packets: replay,
            familyLabel: stopAfterOneCycle && stopPatchCount > 0
                ? "\(replayFamily.label) (one-cycle)"
                : replayFamily.label
        )
    }

    nonisolated private static func makeNoBlackForegroundOverlayReplayPackets(
        lines: [CanvasLinePayload],
        mode: MessageMode,
        basePixels: [ProgressPixel],
        baseFont: AppFont,
        baseColor: AppColor,
        basePalette: AppPalette,
        speedCode: UInt8,
        holdSeconds: Int,
        sequenceTimingCode: UInt8,
        preserveTemplateTiming: Bool
    ) throws -> ForegroundOverlayReplayBuild {
        guard let replayFamily = loadPreferredNoBlackReplayPackets(),
              let templatePair = loadPreferredNoBlackTemplatePair()
        else {
            throw ReplayPatchError.replayTemplateMissing
        }

        let nonEmptyLines = lines.filter { !$0.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmptyLines.isEmpty else {
            throw ReplayPatchError.replayTemplateMissing
        }

        let bmpOffsets = findBmpOffsets(in: templatePair.nmg)
        guard !bmpOffsets.isEmpty else {
            throw ReplayPatchError.replayTemplateMissing
        }

        let renderedFrames: [(line: CanvasLinePayload, bmp: Data, xOffset: Int)] = {
            if mode == .marquee {
                let frameCount = max(1, bmpOffsets.count)
                let marqueeText = nonEmptyLines.map(\.rawText).joined(separator: "   ")
                let marqueeLine = CanvasLinePayload(
                    rowIndex: 0,
                    rawText: marqueeText,
                    serializedText: marqueeText,
                    styleRuns: [],
                    alignment: .left
                )
                return (0..<frameCount).map { index in
                    let progress = frameCount <= 1 ? 1.0 : Double(index) / Double(frameCount - 1)
                    let textWidth = PixelFontRenderer.textWidth(marqueeLine.rawText, baseStyle: baseFont, styleRuns: marqueeLine.styleRuns)
                    let startX = 80
                    let endX = -textWidth - 1
                    let xOffset = Int((Double(startX) + Double(endX - startX) * progress).rounded())
                    let textFrame = bitmapFrameForCanvasLine(
                        marqueeLine,
                        baseFont: baseFont,
                        baseColor: baseColor,
                        basePalette: basePalette,
                        xOffset: xOffset
                    )
                    let mergedPixels = overlayForegroundPixels(base: basePixels, foreground: textFrame.pixels)
                    return (line: marqueeLine, bmp: makeRGB565BMP(width: 80, height: 7, pixels: mergedPixels), xOffset: xOffset)
                }
            } else {
                return nonEmptyLines.map { line in
                    let textFrame = bitmapFrameForCanvasLine(
                        line,
                        baseFont: baseFont,
                        baseColor: baseColor,
                        basePalette: basePalette
                    )
                    let mergedPixels = overlayForegroundPixels(base: basePixels, foreground: textFrame.pixels)
                    return (line: line, bmp: makeRGB565BMP(width: 80, height: 7, pixels: mergedPixels), xOffset: 0)
                }
            }
        }()

        let targetBmps: [Data] = mode == .marquee
            ? renderedFrames.map(\.bmp)
            : (0..<bmpOffsets.count).map { index in
                renderedFrames[index % renderedFrames.count].bmp
            }

        var content = replaceBmpPixelDataAtOffsets(
            in: templatePair.nmg,
            offsets: bmpOffsets,
            bmps: targetBmps
        )
        content = scrubNoBlackTemplateLabels(in: content)
        content = forceStaticBitmapPlayback(in: content)
        if !preserveTemplateTiming {
            content = applyProgramTimingControls(
                in: content,
                speedCode: speedCode,
                holdSeconds: holdSeconds
            )
        }

        let payloadLength = max(1, min(templatePair.payloadLength ?? content.count, content.count))
        content = Data(content.prefix(payloadLength))
        let chunks = content.chunked(maxSize: 768)

        var replay = replayFamily.packets
        let fileChunkIndexes = replay.enumerated().compactMap { index, packet -> Int? in
            guard packet.payload.count >= 24 else { return nil }
            if let command = replayCommand(packet.payload), command == (0x02, 0x04) {
                return index
            }
            return nil
        }
        guard !fileChunkIndexes.isEmpty else { throw ReplayPatchError.noFileChunkPackets }
        guard fileChunkIndexes.count == chunks.count else {
            throw ReplayPatchError.chunkCountMismatch(expected: chunks.count, got: fileChunkIndexes.count)
        }

        for (chunkIdx, packetIndex) in fileChunkIndexes.enumerated() {
            var payload = replay[packetIndex].payload
            let chunk = chunks[chunkIdx]
            guard payload.count >= 24 else { continue }

            let descriptorWords = Int(payload.le16(at: 14))
            let descriptorStart = 16
            let descriptorLength = descriptorWords * 4
            let chunkStart = descriptorStart + descriptorLength
            let oldChunkLength = Int(payload.le32(at: 4))
            let oldChunkEnd = chunkStart + oldChunkLength
            guard chunkStart <= payload.count, oldChunkEnd <= payload.count else { continue }

            payload.setLE32(UInt32(chunk.count), at: 4)
            payload.setLE32(UInt32(content.count), at: descriptorStart + 14)
            payload.setLE16(768, at: descriptorStart + 18)
            payload.setLE16(UInt16(chunks.count), at: descriptorStart + 20)
            payload.setLE16(UInt16(chunkIdx + 1), at: descriptorStart + 22)
            payload.replaceSubrange(chunkStart..<oldChunkEnd, with: chunk)
            payload.rewriteSigmaFrameCRC()

            replay[packetIndex] = SigmaReplayPacket(
                delayMilliseconds: replay[packetIndex].delayMilliseconds,
                sourcePort: replay[packetIndex].sourcePort,
                payload: payload
            )
        }

        var patchedCommit = false
        for idx in replay.indices {
            guard let command = replayCommand(replay[idx].payload), command == (0x02, 0x0e) else {
                continue
            }
            var commit = replay[idx].payload
            let commitBody = 16
            guard commit.count >= commitBody + 40 else { continue }

            commit.setLE32(UInt32(content.count), at: commitBody + 32)
            commit.setLE32(UInt32(sigmaX25(content)), at: commitBody + 36)
            commit.rewriteSigmaFrameCRC()
            replay[idx] = SigmaReplayPacket(
                delayMilliseconds: replay[idx].delayMilliseconds,
                sourcePort: replay[idx].sourcePort,
                payload: commit
            )
            patchedCommit = true
        }
        guard patchedCommit else { throw ReplayPatchError.commitPacketMissing }

        replay = replay.map { packet in
            guard let command = replayCommand(packet.payload), command == (0x02, 0x02) else {
                return packet
            }
            let patchedPayload = patchSequenceTimingCode(in: packet.payload, timingCode: sequenceTimingCode)
            return SigmaReplayPacket(
                delayMilliseconds: packet.delayMilliseconds,
                sourcePort: packet.sourcePort,
                payload: patchedPayload
            )
        }

        let debugLines: [String] = (0..<bmpOffsets.count).map { index in
            let frame = mode == .marquee
                ? renderedFrames[index]
                : renderedFrames[index % renderedFrames.count]
            if mode == .marquee {
                return "Foreground frame \(index + 1): row=\(frame.line.rowIndex + 1) x=\(frame.xOffset) text=\"\(frame.line.rawText)\""
            }
            return "Foreground frame \(index + 1): row=\(frame.line.rowIndex + 1) text=\"\(frame.line.rawText)\""
        }

        return ForegroundOverlayReplayBuild(
            build: BackgroundReplayBuild(
                packets: replay,
                familyLabel: "\(replayFamily.label) (foreground overlay)"
            ),
            frameCount: bmpOffsets.count,
            debugLines: debugLines
        )
    }

    nonisolated private static func replaceFirstAsciiTokenInReplayPackets(
        _ packets: [SigmaReplayPacket],
        from source: String,
        to replacement: String
    ) -> [SigmaReplayPacket] {
        let src = Data(source.utf8)
        let dst = Data(replacement.utf8)
        guard src.count == dst.count else { return packets }
        var patched = packets
        for i in patched.indices {
            var payload = patched[i].payload
            if let range = payload.firstRange(of: src) {
                payload.replaceSubrange(range, with: dst)
                payload.rewriteSigmaFrameCRC()
                patched[i] = SigmaReplayPacket(
                    delayMilliseconds: patched[i].delayMilliseconds,
                    sourcePort: patched[i].sourcePort,
                    payload: payload
                )
                return patched
            }
        }
        return patched
    }

    nonisolated private static func loadCapturedBackgroundReplayPacketsForProgress() -> [SigmaReplayPacket]? {
        // Keep progress on the replay family proven to render on this sign.
        let path = Paths.capturesDirectory.appendingPathComponent("backimage-wire-20260503-013223.replay.tsv").path()
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var packets: [SigmaReplayPacket] = []
        for line in raw.split(whereSeparator: \.isNewline) {
            let text = String(line)
            if text.isEmpty || text.hasPrefix("#") { continue }
            let parts = text.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            guard let delay = Int(parts[0]), let sourcePort = UInt16(parts[1]) else { continue }
            let hex = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let payload = Data(hexString: hex), !payload.isEmpty else { continue }
            packets.append(SigmaReplayPacket(delayMilliseconds: delay, sourcePort: sourcePort, payload: payload))
        }
        return packets.isEmpty ? nil : packets
    }

    private struct BackgroundReplayFamily: Sendable {
        let replayPackets: [SigmaReplayPacket]
        let templatePair: EditorTemplatePair
        let label: String
    }

    nonisolated private static func loadBackgroundReplayFamilyForProgress() -> BackgroundReplayFamily? {
        let cleanReplayPath = Paths.capturesDirectory.appendingPathComponent("backimage-clean-wire-20260503-020018.replay.tsv").path()
        let cleanNmgPath = Paths.capturesDirectory.appendingPathComponent("backimage-clean-live-20260503-020018/temp.Nmg.changed.020035").path()
        let cleanSeqPath = Paths.capturesDirectory.appendingPathComponent("backimage-clean-live-20260503-020018/SequentList.tmps.changed.020035").path()
        if let replayPackets = loadReplayPacketsFromTSV(cleanReplayPath),
           let nmg = try? Data(contentsOf: URL(fileURLWithPath: cleanNmgPath)),
           let seq = try? Data(contentsOf: URL(fileURLWithPath: cleanSeqPath)),
           !nmg.isEmpty,
           !seq.isEmpty {
            let payloadLength = sequencePayloadLength(for: "temp.Nmg", in: seq)
            let templatePair = EditorTemplatePair(
                nmg: nmg,
                sequence: seq,
                payloadLength: payloadLength,
                sourceLabel: "clean backimage 020018"
            )
            return BackgroundReplayFamily(
                replayPackets: replayPackets,
                templatePair: templatePair,
                label: "clean backimage 020018"
            )
        }

        if let replayPackets = loadCapturedBackgroundReplayPacketsForProgress(),
           let templatePair = loadEditorBackgroundTemplatePairWithBMP() {
            return BackgroundReplayFamily(
                replayPackets: replayPackets,
                templatePair: templatePair,
                label: "pinned backimage 013223"
            )
        }
        return nil
    }

    private struct SequenceTimingHint: Sendable {
        let source: String
        let code: UInt8
    }

    nonisolated private static func backgroundReplaySequenceTimingHint() -> SequenceTimingHint? {
        guard let family = loadBackgroundReplayFamilyForProgress(),
              let code = sequenceTimingCode(in: family.templatePair.sequence)
        else {
            return nil
        }
        return SequenceTimingHint(source: family.templatePair.sourceLabel, code: code)
    }

    nonisolated private static func loadReplayPacketsFromTSV(_ path: String) -> [SigmaReplayPacket]? {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var packets: [SigmaReplayPacket] = []
        for line in raw.split(whereSeparator: \.isNewline) {
            let text = String(line)
            if text.isEmpty || text.hasPrefix("#") { continue }
            let parts = text.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            guard let delay = Int(parts[0]), let sourcePort = UInt16(parts[1]) else { continue }
            let hex = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let payload = Data(hexString: hex), !payload.isEmpty else { continue }
            packets.append(SigmaReplayPacket(delayMilliseconds: delay, sourcePort: sourcePort, payload: payload))
        }
        return packets.isEmpty ? nil : packets
    }

    nonisolated private static func loadEditorBackgroundTemplatePair() -> EditorTemplatePair? {
        if let latestCapture = latestCapturedBackImagePair() {
            return latestCapture
        }

        let candidates: [(label: String, nmgPath: String, sequencePath: String)] = [
            (
                "editor-picture template",
                Paths.projectRoot.appendingPathComponent("analysis/templates/editor-picture-template.Nmg").path(),
                Paths.capturesDirectory.appendingPathComponent("editor-live-20260503-005753/SequentList.tmps").path()
            ),
            (
                "editor-live capture",
                Paths.capturesDirectory.appendingPathComponent("editor-live-20260503-005753/temp.Nmg").path(),
                Paths.capturesDirectory.appendingPathComponent("editor-live-20260503-005753/SequentList.tmps").path()
            ),
            (
                "live Editor files",
                Paths.editorNmg.path(),
                Paths.editorSequence.path()
            ),
            (
                "capture A",
                Paths.capturesDirectory.appendingPathComponent("editor-image-seq-A-20260503-004225/temp.Nmg").path(),
                Paths.capturesDirectory.appendingPathComponent("editor-image-seq-A-20260503-004225/SequentList.tmps").path()
            ),
            (
                "capture B",
                Paths.capturesDirectory.appendingPathComponent("editor-image-seq-B-20260503-004300/temp.Nmg").path(),
                Paths.capturesDirectory.appendingPathComponent("editor-image-seq-B-20260503-004300/SequentList.tmps").path()
            ),
            (
                "editor-live capture",
                Paths.capturesDirectory.appendingPathComponent("editor-live-20260503-005753/temp.Nmg").path(),
                Paths.capturesDirectory.appendingPathComponent("editor-live-20260503-005753/SequentList.tmps").path()
            )
        ]

        var fallback: EditorTemplatePair?
        for candidate in candidates {
            guard
                let nmg = try? Data(contentsOf: URL(fileURLWithPath: candidate.nmgPath)),
                let seq = try? Data(contentsOf: URL(fileURLWithPath: candidate.sequencePath)),
                !nmg.isEmpty,
                !seq.isEmpty
            else {
                continue
            }
            let payloadLength = sequencePayloadLength(for: "temp.Nmg", in: seq)
            let pair = EditorTemplatePair(
                nmg: nmg,
                sequence: seq,
                payloadLength: payloadLength,
                sourceLabel: candidate.label
            )
            if isPreferredBackgroundTemplate(nmg, payloadLength: payloadLength) {
                return pair
            }
            if fallback == nil, isLikelyPictureProgram(nmg) {
                fallback = pair
            }
        }
        return fallback
    }

    nonisolated private static func loadEditorBackgroundTemplatePairWithBMP() -> EditorTemplatePair? {
        // Fallback pinned BM-capable capture for dynamic frame mutation.
        let pinnedCaptureNmg = Paths.capturesDirectory.appendingPathComponent("backimage-live-20260503-013223/temp.Nmg.changed.013235").path()
        let pinnedCaptureSeq = Paths.capturesDirectory.appendingPathComponent("backimage-live-20260503-013223/SequentList.tmps.changed.013235").path()
        if let nmg = try? Data(contentsOf: URL(fileURLWithPath: pinnedCaptureNmg)),
           let seq = try? Data(contentsOf: URL(fileURLWithPath: pinnedCaptureSeq)),
           !nmg.isEmpty,
           !seq.isEmpty {
            let payloadLength = sequencePayloadLength(for: "temp.Nmg", in: seq)
            return EditorTemplatePair(
                nmg: nmg,
                sequence: seq,
                payloadLength: payloadLength,
                sourceLabel: "pinned BM capture 013223"
            )
        }

        if let latestBMPCapture = latestCapturedBackImagePair(requireBMP: true) {
            return latestBMPCapture
        }
        return nil
    }

    nonisolated private static func latestCapturedBackImagePair(requireBMP: Bool = false) -> EditorTemplatePair? {
        let root = Paths.capturesDirectory
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let backimageDirs = dirs
            .filter { $0.lastPathComponent.hasPrefix("backimage-live-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        for dir in backimageDirs {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            let nmg = files
                .filter { $0.lastPathComponent.hasPrefix("temp.Nmg.changed.") }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
                .first
                ?? files.first { $0.lastPathComponent == "temp.Nmg.before" }

            let sequence = files
                .filter { $0.lastPathComponent.hasPrefix("SequentList.tmps.changed.") }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
                .first
                ?? files.first { $0.lastPathComponent == "SequentList.tmps.before" }

            guard let nmg, let sequence else { continue }
            guard
                let nmgData = try? Data(contentsOf: nmg),
                let seqData = try? Data(contentsOf: sequence),
                !nmgData.isEmpty,
                !seqData.isEmpty
            else {
                continue
            }

            let payloadLength = sequencePayloadLength(for: "temp.Nmg", in: seqData)
            let pair = EditorTemplatePair(
                nmg: nmgData,
                sequence: seqData,
                payloadLength: payloadLength,
                sourceLabel: "captured \(dir.lastPathComponent)"
            )

            if isPreferredBackgroundTemplate(nmgData, payloadLength: payloadLength, requireBMP: requireBMP) {
                return pair
            }
        }

        return nil
    }

    nonisolated private static func isLikelyPictureProgram(_ data: Data) -> Bool {
        data.starts(with: Data([0x4e, 0x47, 0x50, 0x00])) && data.firstRange(of: Data([0x42, 0x4d])) != nil
    }

    nonisolated private static func isPreferredBackgroundTemplate(_ data: Data, payloadLength: Int?, requireBMP: Bool = false) -> Bool {
        guard data.starts(with: Data([0x4e, 0x47, 0x50, 0x00])) else { return false }
        if requireBMP && !isLikelyPictureProgram(data) { return false }
        guard data.count >= 6500, data.count <= 20000 else { return false }
        if let payloadLength {
            // Accept both known families:
            // - ~9.3k payload from clean background capture
            // - ~10.6k payload from DECEMBER-over-background capture
            if payloadLength >= 9000 && payloadLength <= 11500 { return true }
            if payloadLength >= 1200 && payloadLength <= 1800 { return true }
        }
        return false
    }

    nonisolated private static func sequencePayloadLength(for filename: String, in sequence: Data) -> Int? {
        guard let range = sequence.firstRange(of: Data(filename.utf8)) else { return nil }
        let start = range.lowerBound
        guard start >= 2 else { return nil }
        return Int(sequence[start - 2]) | (Int(sequence[start - 1]) << 8)
    }

    nonisolated private static func replaceBmp(
        inTemplateNmg template: Data,
        with bmp: Data,
        trimAfterBmp: Bool = false
    ) -> Data? {
        guard template.count >= bmp.count else { return nil }
        var offset = 0
        while offset + bmp.count <= template.count {
            guard let marker = template[offset...].firstRange(of: Data([0x42, 0x4d])) else { break }
            let bmOffset = marker.lowerBound
            if bmOffset + bmp.count <= template.count {
                var candidate = template
                candidate.replaceSubrange(bmOffset..<(bmOffset + bmp.count), with: bmp)
                if trimAfterBmp {
                    candidate = candidate.prefix(bmOffset + bmp.count)
                }
                return candidate
            }
            offset = bmOffset + 2
        }
        return nil
    }

    nonisolated private static func replaceAllBmps(
        inTemplateNmg template: Data,
        with bmp: Data,
        trimAfterFirstBmp: Bool = false
    ) -> Data? {
        guard template.count >= bmp.count else { return nil }
        var candidate = template
        var foundAny = false
        var offset = 0
        var firstOffset: Int?
        while offset + 18 < candidate.count {
            guard let marker = candidate[offset...].firstRange(of: Data([0x42, 0x4d])) else { break }
            let bmOffset = marker.lowerBound
            if isLikelyBmpHeader(candidate, at: bmOffset),
               bmOffset + bmp.count <= candidate.count {
                candidate.replaceSubrange(bmOffset..<(bmOffset + bmp.count), with: bmp)
                foundAny = true
                if firstOffset == nil { firstOffset = bmOffset }
                offset = bmOffset + bmp.count
            } else {
                offset = bmOffset + 2
            }
        }
        guard foundAny else { return nil }
        if trimAfterFirstBmp, let firstOffset {
            return candidate.prefix(firstOffset + bmp.count)
        }
        return candidate
    }

    nonisolated private static func isLikelyBmpHeader(_ data: Data, at offset: Int) -> Bool {
        guard offset + 54 <= data.count else { return false }
        // BITMAPINFOHEADER marker at +14 is typically 0x28 00 00 00 for these files.
        return data[offset + 14] == 0x28
            && data[offset + 15] == 0x00
            && data[offset + 16] == 0x00
            && data[offset + 17] == 0x00
    }

    nonisolated private static func suppressLeakedHeaderText(in data: Data) -> Data {
        var result = data
        let target = Data("11001".utf8)
        if let range = result.firstRange(of: target), range.lowerBound < 64 {
            result.replaceSubrange(range, with: Data(repeating: 0x20, count: target.count))
        }
        return result
    }

    nonisolated private static func forceStaticBitmapPlayback(in data: Data) -> Data {
        var result = data
        // If this is an Editor NGP wrapper, force single-scene playback.
        if result.count > 6,
           result[0] == 0x4e, result[1] == 0x47, result[2] == 0x50, result[3] == 0x00 {
            result[4] = 0x01
            result[5] = 0x00
            // Suppress the fixed ASCII header token that leaks as red text (e.g. 11001/11011).
            if result.count > 0x18 {
                result[0x14] = 0x20
                result[0x15] = 0x20
                result[0x16] = 0x20
                result[0x17] = 0x20
                result[0x18] = 0x20
            }
        }

        // NGP/template payloads can contain multiple effect blocks.
        // Force every In/Out marker to Editor "Jump out" (0).
        var i = 0
        while i + 2 < result.count {
            if result[i] == 0x0a, result[i + 1] == 0x49 {
                result[i + 2] = 0x30 // I0
                i += 3
                continue
            }
            if result[i] == 0x0a, result[i + 1] == 0x4f {
                result[i + 2] = 0x30 // O0
                i += 3
                continue
            }
            i += 1
        }
        return result
    }

    nonisolated private static func applyProgramTimingControls(
        in data: Data,
        speedCode: UInt8,
        holdSeconds: Int
    ) -> Data {
        var result = data
        let clampedSpeed = (speedCode >= UInt8(ascii: "0") && speedCode <= UInt8(ascii: "9"))
            ? speedCode
            : UInt8(ascii: "2")
        let holdDigit = UInt8(ascii: "0") + UInt8(max(0, min(9, holdSeconds)))

        var i = 0
        while i + 1 < result.count {
            if result[i] == 0x0f {
                let next = result[i + 1]
                if next >= UInt8(ascii: "0"), next <= UInt8(ascii: "9") {
                    result[i + 1] = clampedSpeed
                }
            } else if result[i] == 0x07 {
                let next = result[i + 1]
                if next >= UInt8(ascii: "0"), next <= UInt8(ascii: "9") {
                    result[i + 1] = holdDigit
                }
            }
            i += 1
        }
        return result
    }

    nonisolated private static func progressTransportFloorSeconds(for speed: SigmaSpeed) -> Double {
        switch speed {
        case .veryFast:
            return 1.02
        case .fast:
            return 1.04
        case .mediumFast:
            return 1.06
        case .medium:
            return 1.10
        case .mediumSlow:
            return 1.16
        case .slow:
            return 1.22
        case .verySlow:
            return 1.28
        }
    }

    nonisolated private static func progressReplayDisplayFloorSeconds(for speed: SigmaSpeed) -> Double {
        switch speed {
        case .veryFast:
            return 1.70
        case .fast:
            return 1.80
        case .mediumFast:
            return 1.90
        case .medium:
            return 2.00
        case .mediumSlow:
            return 2.10
        case .slow:
            return 2.20
        case .verySlow:
            return 2.30
        }
    }

    nonisolated private static func noBlackEstimatedStepSeconds(for speed: SigmaSpeed) -> Double {
        switch speed {
        case .veryFast:
            return 1.35
        case .fast:
            return 1.40
        case .mediumFast:
            return 1.50
        case .medium:
            return 1.60
        case .mediumSlow:
            return 1.70
        case .slow:
            return 1.80
        case .verySlow:
            return 1.90
        }
    }

    nonisolated private static func noBlackObservedStepSeconds(for speed: SigmaSpeed) -> Double {
        // Empirical on-device stepping for the known-good 10-frame no-black capture family.
        // These are intentionally conservative so the final static latch lands near end-of-cycle.
        switch speed {
        case .veryFast:
            return 1.30
        case .fast:
            return 1.40
        case .mediumFast:
            return 1.50
        case .medium:
            return 1.60
        case .mediumSlow:
            return 1.70
        case .slow:
            return 1.80
        case .verySlow:
            return 1.90
        }
    }

    nonisolated private static func noBlackStartupDelaySeconds(for speed: SigmaSpeed) -> Double {
        // Sign-side decode/start latency before first visible frame.
        switch speed {
        case .veryFast:
            return 4.2
        case .fast:
            return 4.5
        case .mediumFast:
            return 5.0
        case .medium:
            return 5.3
        case .mediumSlow:
            return 5.6
        case .slow:
            return 6.0
        case .verySlow:
            return 6.4
        }
    }

    nonisolated private static func noBlackTemplateFrameCount() -> Int? {
        guard let pair = loadPreferredNoBlackTemplatePair() else { return nil }
        let count = findBmpOffsets(in: pair.nmg).count
        return count > 0 ? count : nil
    }

    nonisolated private static func makeRGB565BMP(width: Int, height: Int, pixels: [ProgressPixel]) -> Data {
        let bytesPerPixel = 2
        let rowBytes = width * bytesPerPixel
        let rowStride = ((rowBytes + 3) / 4) * 4
        let imageSize = rowStride * height
        let pixelOffset = 14 + 40 + 12
        let fileSize = pixelOffset + imageSize

        var data = Data()
        data.append(contentsOf: [0x42, 0x4d])
        data.appendLE32(UInt32(fileSize))
        data.appendLE16(0)
        data.appendLE16(0)
        data.appendLE32(UInt32(pixelOffset))
        data.appendLE32(40)
        data.appendLE32(UInt32(width))
        data.appendLE32(UInt32(height))
        data.appendLE16(1)
        data.appendLE16(16)
        data.appendLE32(3)
        data.appendLE32(UInt32(imageSize))
        data.appendLE32(0)
        data.appendLE32(0)
        data.appendLE32(0)
        data.appendLE32(0)
        data.appendLE32(0x0000f800)
        data.appendLE32(0x000007e0)
        data.appendLE32(0x0000001f)

        let padding = rowStride - rowBytes
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in 0..<width {
                data.appendLE16(pixels[y * width + x].rgb565)
            }
            if padding > 0 {
                data.append(contentsOf: repeatElement(UInt8(0), count: padding))
            }
        }
        return data
    }

    func chooseConfigSource() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.nameFieldStringValue = "SysInfoFile"
        if panel.runModal() == .OK, let url = panel.url {
            systemConfigSourcePath = url.path()
            systemStatus = "Selected \(url.lastPathComponent)"
        }
    }

    func prepareSystemConfig() {
        do {
            let source = URL(fileURLWithPath: systemConfigSourcePath)
            var data = try Data(contentsOf: source)
            try patchSysInfoFile(&data)

            let output = URL(fileURLWithPath: Paths.buildDirectory.appendingPathComponent("prepared-SysInfoFile").path())
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: output, options: .atomic)

            preparedConfigPath = output.path()
            systemStatus = "Prepared SysInfoFile for \(systemName) at \(systemIP)"
            appendMessageLog(systemStatus)
        } catch {
            systemStatus = "Could not prepare SysInfoFile"
            appendMessageLog("Config prepare error: \(error)")
        }
    }

    func uploadPreparedSystemConfig() {
        guard !isSending else { return }
        guard let port = UInt16(signPort) else {
            appendMessageLog("Invalid port: \(signPort)")
            return
        }
        guard !preparedConfigPath.isEmpty else { return }

        let host = signIP
        let path = preparedConfigPath
        isSending = true
        lastSendSucceeded = false
        systemStatus = "Uploading SysInfoFile to \(host)"
        appendMessageLog("Uploading prepared SysInfoFile. Sign may beep/reboot or may move to \(systemIP).")

        Task.detached {
            do {
                let content = try Data(contentsOf: URL(fileURLWithPath: path))
                var client = SigmaClient(host: host, port: port)
                let steps = try client.sendSystemFile(name: "SysInfoFile", content: content)
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = true
                    self.systemStatus = "SysInfoFile uploaded"
                    self.messageStatus = "Config uploaded"
                    for step in steps {
                        self.appendMessageLog(step)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = false
                    self.systemStatus = "Config upload failed"
                    self.messageStatus = "Config upload failed"
                    self.appendMessageLog("Config upload error: \(error)")
                }
            }
        }
    }

    func probeSigmaCandidates() {
        for ip in sigmaCandidateIPs {
            for port in sigmaCandidatePorts {
                probeTCP(host: ip, port: UInt16(port), text: networkProbeText)
            }
        }
    }

    func probeTCP(host: String, port: UInt16, text: String) {
        let target = "\(host):\(port)"
        addLog("TCP probe \(target): \(text)")
        probeResults.append(ProbeResult(target: target, status: "Trying", response: ""))
        Task.detached {
            let response = await TCPProbe.probe(host: host, port: port, text: text)
            await MainActor.run {
                if let idx = self.probeResults.lastIndex(where: { $0.target == target && $0.status == "Trying" }) {
                    self.probeResults[idx] = ProbeResult(target: target, status: response.ok ? "Open" : "Closed", response: response.message)
                }
                self.addLog("\(target): \(response.message)")
            }
        }
    }

    func addLog(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        logLines.append("[\(stamp)] \(line)")
    }

    func appendMessageLog(_ line: String) {
        let stamp = Self.messageLogStampFormatter.string(from: Date())
        let rendered = "[\(stamp)] \(line)"
        messageLog.append(rendered)
        appendMessageLogToFile(rendered)
    }

    // MARK: - Plex

    func refreshPlexNowPlaying() {
        Task {
            await plexService.configure(serverURL: plexServerURL, token: plexToken)
            let result = await plexService.fetchNowPlaying()
            await MainActor.run {
                switch result {
                case .success(let items):
                    let previousItems = plexNowPlaying
                    plexNowPlaying = items

                    if items.isEmpty {
                        plexStatus = "Nothing playing"
                        if plexAutoSend && !previousItems.isEmpty {
                            plexPendingSendTask?.cancel()
                            queuePlexSend(stopped: true)
                        }
                    } else {
                        let names = items.map { "\($0.user): \($0.displayTitle) (\($0.state))" }.joined(separator: ", ")
                        plexStatus = names

                        if plexAutoSend {
                            let currentKey = Self.plexMediaKey(for: items)
                            if currentKey != plexLastMediaKey {
                                plexLastMediaKey = currentKey
                                plexPendingSendTask?.cancel()
                                queuePlexSend(stopped: false)
                            }
                        }
                    }
                case .failure(let error):
                    plexStatus = error.localizedDescription
                }
            }
        }
    }

    private static func plexMediaKey(for items: [PlexNowPlaying]) -> String {
        items.map(\.displayTitle).joined(separator: ";")
    }

    private func queuePlexSend(stopped: Bool) {
        let elapsed = Date().timeIntervalSince(plexLastSentTime)
        let cooldown = TimeInterval(plexMinSendInterval)
        guard elapsed >= cooldown else {
            plexStatus = "Auto-send: cooldown (\(Int(cooldown - elapsed))s left)"
            return
        }

        plexPendingSendTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.plexSendDelaySeconds ?? 10) * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if stopped {
                self.sendPlexStoppedToSign()
            } else {
                self.sendPlexNowPlayingToSign()
            }
        }
    }

    func startPlexAutoRefresh() {
        plexRefreshTask?.cancel()
        plexRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshPlexNowPlaying()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func stopPlexAutoRefresh() {
        plexRefreshTask?.cancel()
        plexRefreshTask = nil
    }

    func sendPlexNowPlayingToSign() {
        guard !plexNowPlaying.isEmpty else {
            plexStatus = "Nothing playing to send"
            return
        }
        let item = plexNowPlaying[0]
        let text = plexFormatTemplate
            .replacingOccurrences(of: "{title}", with: item.displayTitle)
            .replacingOccurrences(of: "{user}", with: item.user)
            .replacingOccurrences(of: "{type}", with: item.type)
            .replacingOccurrences(of: "{progress}", with: "\(item.progressPercent)%")
            .replacingOccurrences(of: "{remaining}", with: item.timeRemainingFormatted)
            .replacingOccurrences(of: "{endtime}", with: item.endTimeFormatted)
        plexLastSentText = text

        guard let port = UInt16(signPort) else {
            plexStatus = "Invalid port"
            return
        }
        let host = signIP
        let plexSendFont = plexFont
        let plexSendColor = plexPalette.sendColor(base: plexColor)
        let useEditorFontCompat = senderProfile == .editorFont

        let speedCode = speed.sigmaCode
        isSending = true
        lastSendSucceeded = false
        messageStatus = "Sending Plex now-playing to \(host)"
        appendMessageLog("Plex: \(text)")

        Task.detached {
            do {
                var client = SigmaClient(host: host, port: port)
                let options = SigmaTextOptions(
                    inEffectCode: UInt8(ascii: "1"),
                    outEffectCode: UInt8(ascii: "1"),
                    speedCode: speedCode,
                    horizontalAlignCode: UInt8(ascii: "0"),
                    verticalAligns: false,
                    holdSeconds: 5,
                    wrapsText: false
                )
                let steps = try client.sendText(
                    text,
                    font: plexSendFont.sigmaFont,
                    color: plexSendColor,
                    options: options,
                    editorFontCompat: useEditorFontCompat
                )
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = true
                    self.plexLastSentTime = Date()
                    self.messageStatus = "Plex sent"
                    self.plexStatus = "Sent: \(text)"
                    for step in steps {
                        self.appendMessageLog(step)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = false
                    self.messageStatus = "Plex send failed"
                    self.plexStatus = "Error: \(error)"
                }
            }
        }
    }

    func sendPlexStoppedToSign() {
        plexLastMediaKey = ""
        let text = "Plex: Stopped"
        plexLastSentText = text

        guard let port = UInt16(signPort) else {
            plexStatus = "Invalid port"
            return
        }
        let host = signIP
        let plexSendFont = plexFont
        let plexSendColor = plexPalette.sendColor(base: plexColor)
        let useEditorFontCompat = senderProfile == .editorFont
        let speedCode = speed.sigmaCode

        isSending = true
        lastSendSucceeded = false
        messageStatus = "Sending Plex stopped to \(host)"
        appendMessageLog("Plex: Stopped")

        Task.detached {
            do {
                var client = SigmaClient(host: host, port: port)
                let options = SigmaTextOptions(
                    inEffectCode: UInt8(ascii: "1"),
                    outEffectCode: UInt8(ascii: "1"),
                    speedCode: speedCode,
                    horizontalAlignCode: UInt8(ascii: "0"),
                    verticalAligns: false,
                    holdSeconds: 5,
                    wrapsText: false
                )
                let steps = try client.sendText(
                    text,
                    font: plexSendFont.sigmaFont,
                    color: plexSendColor,
                    options: options,
                    editorFontCompat: useEditorFontCompat
                )
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = true
                    self.plexLastSentTime = Date()
                    self.messageStatus = "Plex stopped sent"
                    self.plexStatus = "Sent: Stopped"
                    for step in steps {
                        self.appendMessageLog(step)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSending = false
                    self.lastSendSucceeded = false
                    self.messageStatus = "Plex send failed"
                    self.plexStatus = "Error: \(error)"
                }
            }
        }
    }

    private func startRuntimeCommandWatcher() {
        commandWatcherTask?.cancel()
        commandWatcherTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.consumeRuntimeCommandIfPresent()
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private func consumeRuntimeCommandIfPresent() {
        let url = Self.commandFileURL
        guard FileManager.default.fileExists(atPath: url.path()) else { return }
        do {
            let data = try Data(contentsOf: url)
            try FileManager.default.removeItem(at: url)
            let command = try JSONDecoder().decode(RuntimeCommand.self, from: data)
            applyRuntimeCommand(command)
        } catch {
            appendMessageLog("Command error: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func applyRuntimeCommand(_ command: RuntimeCommand) {
        if let duration = command.duration {
            progressDurationSeconds = max(1, min(300, duration))
        }
        if let frames = command.frames {
            progressFrameCount = max(2, min(40, frames))
        }
        if let stop = command.stopAfterOneCycle {
            progressStopAfterOneCycle = stop
        }
        if let engine = command.engine {
            let normalized = engine.lowercased()
            if let selected = ProgressSendEngine.allCases.first(where: { $0.rawValue.lowercased() == normalized || $0.label.lowercased() == normalized }) {
                progressSendEngine = selected
            }
        }

        switch command.action.lowercased() {
        case "start_progress", "start_timer", "go":
            appendMessageLog("Command: start progress")
            sendProgressAnimation()
        case "send_empty":
            appendMessageLog("Command: send empty progress")
            sendProgressBar(fill: 0)
        case "send_half":
            appendMessageLog("Command: send half progress")
            sendProgressBar(fill: 0.5)
        case "send_full":
            appendMessageLog("Command: send full progress")
            sendProgressBar(fill: 1.0)
        case "probe":
            appendMessageLog("Command: probe sign")
            probeSignStatus()
        case "send_canvas":
            appendMessageLog("Command: send canvas")
            sendCurrentMessage()
        default:
            appendMessageLog("Command ignored: unknown action '\(command.action)'")
        }
    }

    private func appendMessageLogToFile(_ line: String) {
        let url = Self.messageLogFileURL
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let payload = Data((line + "\n").utf8)
            if FileManager.default.fileExists(atPath: url.path()) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: payload)
            } else {
                try payload.write(to: url, options: .atomic)
            }
        } catch {
            // Keep UI log path resilient; file logging is diagnostic only.
            logLines.append("[\(ISO8601DateFormatter().string(from: Date()))] message-log-file-error: \(error.localizedDescription)")
        }
    }

    func addPlaylistItem() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        playlistItems.append(PlaylistItem(text: text, inMode: inMode, outMode: outMode, speed: speed, pauseSeconds: pauseSeconds))
    }

    private func optionsForCurrentMessage() -> SigmaTextOptions {
        Self.optionsForCanvas(mode: messageMode, inMode: inMode, outMode: outMode, speed: speed, holdSeconds: pauseSeconds, verticalAligns: verticalAligns)
    }

    nonisolated private static func optionsForCanvas(
        mode: MessageMode,
        inMode: SigmaEffect,
        outMode: SigmaEffect,
        speed: SigmaSpeed,
        holdSeconds: Int,
        verticalAligns: Bool,
        alignment: CanvasAlignment = .left,
        perRowEffects: [SigmaTextOptions.RowEffect?]? = nil
    ) -> SigmaTextOptions {
        switch mode {
        case .fitted:
            // Stack: all rows on one page. Jump Out so all rows appear
            // simultaneously (no per-row scroll inside the page).
            return SigmaTextOptions(
                inEffectCode: SigmaEffect.jumpOutCode,
                outEffectCode: SigmaEffect.jumpOutCode,
                speedCode: speed.sigmaCode,
                horizontalAlignCode: alignment.sigmaCode,
                verticalAligns: verticalAligns,
                holdSeconds: holdSeconds,
                renderMode: .stack
            )
        case .marquee:
            // Marquee: continuous scroll, all rows joined. Random in/out
            // per Editor capture, align '1'.
            return SigmaTextOptions(
                inEffectCode: UInt8(0x2f),
                outEffectCode: UInt8(0x2f),
                speedCode: speed.sigmaCode,
                horizontalAlignCode: UInt8(ascii: "1"),
                verticalAligns: verticalAligns,
                holdSeconds: holdSeconds,
                renderMode: .marquee
            )
        case .slides:
            // Slides: each row = own page, user-chosen In/Out per row.
            return SigmaTextOptions(
                inEffectCode: inMode.sigmaCode,
                outEffectCode: outMode.sigmaCode,
                speedCode: speed.sigmaCode,
                horizontalAlignCode: alignment.sigmaCode,
                verticalAligns: verticalAligns,
                holdSeconds: holdSeconds,
                renderMode: .slides,
                perRowEffects: perRowEffects
            )
        }
    }

    func addMessageRow() {
        guard messageRows.count < 7 else { return }
        let nextOrder = (messageRows.map(\.order).max() ?? -1) + 1
        let row = MessageRow(
            order: nextOrder,
            text: "",
            mode: messageMode,
            font: font,
            color: color,
            palette: palette,
            inMode: inMode,
            outMode: outMode,
            speed: speed,
            pauseSeconds: pauseSeconds
        )
        messageRows.append(row)
        selectedMessageRowID = row.id
        renumberMessageRows()
    }

    func removeSelectedMessageRow() {
        guard messageRows.count > 1 else { return }
        let selectedID = selectedMessageRow.id
        messageRows.removeAll { $0.id == selectedID }
        renumberMessageRows()
        selectedMessageRowID = messageRows.first?.id
    }

    func setSelectedRowText(_ value: String) {
        setCanvasText(value)
    }

    func setCanvasText(_ value: String) {
        messageText = value
        canvasStyleRuns.removeAll()
        selectedTextRange = NSRange(location: (value as NSString).length, length: 0)
    }

    func updateCanvasSelection(range: NSRange) {
        selectedTextRange = range
        if range.length > 0 {
            lastCanvasSelectionRange = range
        }
    }

    func setActiveCanvasAlignment(_ alignment: CanvasAlignment) {
        let rows = selectedCanvasRowIndexes
        let maxRow = rows.max() ?? 0
        if canvasRowAlignments.count < max(7, maxRow + 1) {
            canvasRowAlignments.append(contentsOf: repeatElement(.left, count: max(7, maxRow + 1) - canvasRowAlignments.count))
        }
        var updated = canvasRowAlignments
        for row in rows {
            updated[row] = alignment
        }
        canvasRowAlignments = updated
    }

    func updateSelectedTextRange(rowID: MessageRow.ID, range: NSRange) {
        selectedMessageRowID = rowID
        updateCanvasSelection(range: range)
    }

    private func renumberMessageRows() {
        for index in messageRows.indices {
            messageRows[index].order = index
        }
    }

    nonisolated static func makeDefaultMessageRows() -> [MessageRow] {
        (0..<7).map { index in
            MessageRow(
                order: index,
                text: index == 0 ? "MAC APP ONLINE" : "",
                mode: .fitted,
                font: .normal7,
                color: .red,
                palette: .solid,
                inMode: SigmaEffect.all[1],
                outMode: SigmaEffect.all[1],
                speed: .mediumFast,
                pauseSeconds: 2
            )
        }
    }

    nonisolated private static func optionsForHeadline(
        _ line: String,
        mode: HeadlineMode,
        font: SigmaFont,
        speed: SigmaSpeed,
        holdSeconds: Int
    ) -> SigmaTextOptions {
        let shouldScroll: Bool
        switch mode {
        case .auto:
            shouldScroll = visibleWidth(line) > font.maxCharactersPerLine
        case .fitted:
            shouldScroll = false
        case .marquee:
            shouldScroll = true
        }

        if shouldScroll {
            return SigmaTextOptions(
                inEffectCode: UInt8(ascii: "1"),
                outEffectCode: UInt8(ascii: "1"),
                speedCode: speed.sigmaCode,
                holdSeconds: holdSeconds,
                wrapsText: false
            )
        }

        return SigmaTextOptions(
            inEffectCode: SigmaEffect.jumpOutCode,
            outEffectCode: SigmaEffect.jumpOutCode,
            speedCode: speed.sigmaCode,
            holdSeconds: holdSeconds,
            wrapsText: true
        )
    }

    nonisolated private static func visibleWidth(_ value: String) -> Int {
        var width = 0
        var index = value.startIndex
        while index < value.endIndex {
            if value[index] == "{", let end = value[index...].firstIndex(of: "}") {
                let token = String(value[value.index(after: index)..<end]).lowercased()
                if Self.zeroWidthMarkupTokens.contains(token) {
                    width += 0
                } else {
                    width += ["hour", "minute", "second"].contains(token) ? 2 : 5
                }
                index = value.index(after: end)
                continue
            }
            width += 1
            index = value.index(after: index)
        }
        return width
    }

    nonisolated static func normalizeSignText(_ value: String) -> String {
        var normalized = value
        let replacements: [(String, String)] = [
            ("\u{201c}", ""),
            ("\u{201d}", ""),
            ("\u{201e}", ""),
            ("\u{00ab}", ""),
            ("\u{00bb}", ""),
            ("\u{2018}", "'"),
            ("\u{2019}", "'"),
            ("\u{201a}", "'"),
            ("\u{201b}", "'"),
            ("\u{2026}", "..."),
            ("\u{2013}", "-"),
            ("\u{2014}", "-"),
            ("\u{2212}", "-"),
            ("\u{00a3}", "{pound}"),
            ("\u{00a0}", " "),
            (";", ",")
        ]
        for (source, target) in replacements {
            normalized = normalized.replacingOccurrences(of: source, with: target)
        }

        var result = ""
        for scalar in normalized.unicodeScalars {
            switch scalar.value {
            case 10, 13:
                result.unicodeScalars.append(scalar)
            case 32...126:
                result.unicodeScalars.append(scalar)
            default:
                result.append(" ")
            }
        }
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result
    }

    nonisolated static func sanitizeSignText(_ value: String) -> String {
        let normalized = normalizeSignText(value)
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -/:.{}_\n\r!@#$%^&*()_+=?,<>[]'")
        var result = ""
        for character in normalized {
            if allowed.contains(character) {
                result.append(character)
            } else {
                result.append(" ")
            }
        }
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static let zeroWidthMarkupTokens = Set([
        "red",
        "green",
        "orange",
        "yellow",
        "bands",
        "characters",
        "diagonal_down",
        "diagonal_up",
        "font5",
        "font7"
    ])

    nonisolated private static let dynamicDisplayTokenPattern = try! NSRegularExpression(
        pattern: #"\{(hour|minute|second|hhmm24|hhmm12|day_name|day_short|day_number|day_ordinal|month_name|month_short|month_number|year|year_short|date_long|date_short_uk|date_compact_uk|date_uk|date_us)\}"#,
        options: [.caseInsensitive]
    )

    nonisolated static func stripZeroWidthMarkup(from value: String) -> String {
        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            if value[index] == "{", let end = value[index...].firstIndex(of: "}") {
                let token = String(value[value.index(after: index)..<end]).lowercased()
                if zeroWidthMarkupTokens.contains(token) {
                    index = value.index(after: end)
                    continue
                }
            }
            result.append(value[index])
            index = value.index(after: index)
        }
        return result
    }

    nonisolated private static func textOnlySerializedLine(_ value: String) -> String {
        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            if value[index] == "{", let end = value[index...].firstIndex(of: "}") {
                let token = String(value[value.index(after: index)..<end]).lowercased()
                if ["font5", "font7"].contains(token) {
                    index = value.index(after: end)
                    continue
                }
            }
            result.append(value[index])
            index = value.index(after: index)
        }
        return result
    }

    nonisolated static func containsDynamicDisplayTokens(_ value: String) -> Bool {
        dynamicDisplayTokenPattern.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)) != nil
    }

    nonisolated static func displayTextForCanvas(_ value: String, date: Date = Date()) -> String {
        replaceDynamicTokens(in: value, date: date, includeSignNativeDateTokens: true)
    }

    nonisolated static func expandAppOnlyDateTokens(_ value: String, date: Date = Date()) -> String {
        replaceDynamicTokens(in: value, date: date, includeSignNativeDateTokens: false)
    }

    nonisolated private static func replaceDynamicTokens(in value: String, date: Date, includeSignNativeDateTokens: Bool) -> String {
        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            if value[index] == "{", let end = value[index...].firstIndex(of: "}") {
                let token = String(value[value.index(after: index)..<end]).lowercased()
                if let replacement = dynamicTokenValue(token, date: date, includeSignNativeDateTokens: includeSignNativeDateTokens) {
                    result += replacement
                    index = value.index(after: end)
                    continue
                }
            }
            result.append(value[index])
            index = value.index(after: index)
        }
        return result
    }

    nonisolated private static func dynamicTokenValue(_ token: String, date: Date, includeSignNativeDateTokens: Bool) -> String? {
        switch token {
        case "hour":
            return formatDate(date, "HH")
        case "minute":
            return formatDate(date, "mm")
        case "second":
            return formatDate(date, "ss")
        case "hhmm24":
            return formatDate(date, "HH:mm")
        case "hhmm12":
            return formatDate(date, "hh:mm a")
        case "day_name":
            return formatDate(date, "EEEE")
        case "day_short":
            return formatDate(date, "EEE")
        case "day_number":
            return formatDate(date, "dd")
        case "day_ordinal":
            return ordinalDay(date)
        case "month_name":
            return formatDate(date, "MMMM")
        case "month_short":
            return formatDate(date, "MMM")
        case "month_number":
            return formatDate(date, "MM")
        case "year":
            return formatDate(date, "yyyy")
        case "year_short":
            return formatDate(date, "yy")
        case "date_long":
            return "\(formatDate(date, "EEEE")) \(ordinalDay(date)) \(formatDate(date, "MMMM yyyy"))"
        case "date_short_uk":
            return formatDate(date, "dd/MM/yy")
        case "date_compact_uk":
            return "\(formatDate(date, "EEE")) \(formatDate(date, "dd/MM/yy"))"
        case "date_uk":
            return includeSignNativeDateTokens ? formatDate(date, "dd/MM/yy") : nil
        case "date_us":
            return includeSignNativeDateTokens ? formatDate(date, "MM/dd/yy") : nil
        default:
            return nil
        }
    }

    nonisolated private static func formatDate(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    nonisolated private static func ordinalDay(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        let suffix: String
        if (11...13).contains(day % 100) {
            suffix = "th"
        } else {
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }

    nonisolated static func previewText(from value: String) -> String {
        stripZeroWidthMarkup(from: value)
            .replacingOccurrences(of: "{POUND}", with: "£")
            .replacingOccurrences(of: "{pound}", with: "£")
    }

    nonisolated static func serializeCanvasText(
        _ text: String,
        styleRuns: [CanvasStyleRun],
        colorRestoreToken: String,
        fontRestoreToken: String
    ) -> String {
        let textLength = (text as NSString).length
        let validRuns = styleRuns
            .filter { $0.length > 0 && $0.location >= 0 && $0.location < textLength }

        var starts: [Int: [CanvasStyleRun]] = [:]
        var ends: [Int: [CanvasStyleRun]] = [:]
        for run in validRuns {
            let clampedLength = min(run.length, textLength - run.location)
            let clampedRun = CanvasStyleRun(location: run.location, length: clampedLength, token: run.token)
            starts[clampedRun.location, default: []].append(clampedRun)
            ends[clampedRun.location + clampedRun.length, default: []].append(clampedRun)
        }

        var result = ""
        let nsText = text as NSString
        for offset in 0...textLength {
            for run in (ends[offset] ?? []).sorted(by: restoreSort) {
                result += restoreToken(for: run.token, colorRestoreToken: colorRestoreToken, fontRestoreToken: fontRestoreToken)
            }
            for run in (starts[offset] ?? []).sorted(by: startSort) {
                result += run.token
            }
            if offset < textLength,
               let scalar = UnicodeScalar(nsText.character(at: offset)) {
                result.append(Character(scalar))
            }
        }
        return result
    }

    nonisolated private static func startSort(_ lhs: CanvasStyleRun, _ rhs: CanvasStyleRun) -> Bool {
        styleTokenPriority(lhs.token) < styleTokenPriority(rhs.token)
    }

    nonisolated private static func restoreSort(_ lhs: CanvasStyleRun, _ rhs: CanvasStyleRun) -> Bool {
        styleTokenPriority(lhs.token) > styleTokenPriority(rhs.token)
    }

    nonisolated private static func restoreToken(for token: String, colorRestoreToken: String, fontRestoreToken: String) -> String {
        switch styleTokenKind(token) {
        case .font:
            return fontRestoreToken
        case .color:
            return colorRestoreToken
        case .other:
            return ""
        }
    }

    nonisolated private enum StyleTokenKind {
        case color
        case font
        case other
    }

    nonisolated private static func styleTokenPriority(_ token: String) -> Int {
        switch styleTokenKind(token) {
        case .color: return 0
        case .font: return 1
        case .other: return 2
        }
    }

    nonisolated private static func styleTokenKind(_ token: String) -> StyleTokenKind {
        switch token.lowercased() {
        case "{font5}", "{font7}":
            return .font
        case "{red}", "{green}", "{orange}", "{yellow}", "{bands}", "{characters}", "{diagonal_down}", "{diagonal_up}":
            return .color
        default:
            return .other
        }
    }

    /// Detect the first font token in serialized text (e.g. "{font5}Hello{font7}").
    nonisolated private static func detectFont(in serializedText: String, fallback: AppFont) -> AppFont {
        var index = serializedText.startIndex
        while index < serializedText.endIndex {
            if serializedText[index] == "{", let end = serializedText[index...].firstIndex(of: "}") {
                let token = String(serializedText[serializedText.index(after: index)..<end]).lowercased()
                if token == "font5" { return .normal5 }
                if token == "font7" { return .normal7 }
            }
            index = serializedText.index(after: index)
        }
        return fallback
    }

    nonisolated static func parseVisibleMarkup(_ text: String) -> (text: String, styleRuns: [CanvasStyleRun], changed: Bool) {
        var output = ""
        var runs: [CanvasStyleRun] = []
        var activeToken: String?
        var activeStart = 0
        var index = text.startIndex
        var changed = false

        func closeRun(at location: Int) {
            guard let token = activeToken, location > activeStart else { return }
            runs.append(CanvasStyleRun(location: activeStart, length: location - activeStart, token: "{\(token)}"))
        }

        while index < text.endIndex {
            if text[index] == "{", let end = text[index...].firstIndex(of: "}") {
                let token = String(text[text.index(after: index)..<end]).lowercased()
                if zeroWidthMarkupTokens.contains(token) {
                    closeRun(at: (output as NSString).length)
                    activeToken = token
                    activeStart = (output as NSString).length
                    changed = true
                    index = text.index(after: end)
                    continue
                }
            }
            output.append(text[index])
            index = text.index(after: index)
        }
        closeRun(at: (output as NSString).length)
        return (output, runs, changed)
    }

    private func patchConfig(_ data: inout Data, ip: String, mask: String, gateway: String) throws {
        guard data.count >= 0x90 else { throw AppError.message("CONFIG.SYS is too small") }
        try writeIPv4(ip, to: &data, offset: 0x24)
        try writeIPv4(gateway, to: &data, offset: 0x88)
        try writeIPv4(mask, to: &data, offset: 0x8c)
    }

    private func patchSysInfoFile(_ data: inout Data) throws {
        guard data.count >= 216 else { throw AppError.message("SysInfoFile is too small") }
        guard data[0] == 0xaa, data[1] == 0x55 else { throw AppError.message("SysInfoFile magic mismatch") }
        guard data[2] == 0x50, data[3] == 0x00, data[4] == 0x07, data[5] == 0x00 else {
            throw AppError.message("Refusing to write non-80x7 SysInfoFile template")
        }

        data[0x20] = UInt8(clamping: systemGroupAddress)
        data[0x21] = UInt8(clamping: systemUnitAddress)
        try writeIPv4(systemIP, to: &data, offset: 0x24)
        try writePowerSchedule(to: &data)
        try writeHalfBrightness(to: &data)
        try writeSerialNumber(to: &data)
        try writeDisplayName(to: &data)
        try writeIPv4(systemGateway, to: &data, offset: 0x88)
        try writeIPv4(systemMask, to: &data, offset: 0x8c)
    }

    private func writePowerSchedule(to data: inout Data) throws {
        data[0x34] = systemPowerEnabled ? 0x01 : 0x00
        let off = try parseHHMM(systemPowerOff)
        let on = try parseHHMM(systemPowerOn)
        data[0x35] = off.hour
        data[0x36] = off.minute
        data[0x37] = on.hour
        data[0x38] = on.minute
    }

    private func writeHalfBrightness(to data: inout Data) throws {
        data[0x40] = systemHalfBrightnessEnabled ? 0x01 : 0x00
        let start = try parseHHMM(systemHalfBrightnessStart)
        let end = try parseHHMM(systemHalfBrightnessEnd)
        data[0x41] = start.hour
        data[0x42] = start.minute
        data[0x43] = end.hour
        data[0x44] = end.minute
    }

    private func writeSerialNumber(to data: inout Data) throws {
        let digits = systemSerialNumber.filter(\.isNumber)
        guard digits.count <= 11 else { throw AppError.message("Serial number must be 11 digits or fewer") }
        data[0x55] = UInt8(digits.count)
        let bytes = Array(digits.utf8)
        for i in 0..<12 {
            data[0x56 + i] = i < bytes.count ? bytes[i] : 0
        }
    }

    private func writeDisplayName(to data: inout Data) throws {
        let bytes = Array(systemName.utf8.prefix(10))
        data[0x6a] = UInt8(bytes.count)
        for i in 0..<10 {
            data[0x6b + i] = i < bytes.count ? bytes[i] : 0
        }
    }

    private func parseHHMM(_ value: String) throws -> (hour: UInt8, minute: UInt8) {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = UInt8(parts[0]),
              let minute = UInt8(parts[1]),
              hour < 24,
              minute < 60 else {
            throw AppError.message("Invalid time: \(value). Use HH:MM")
        }
        return (hour, minute)
    }

    private func writeIPv4(_ value: String, to data: inout Data, offset: Int) throws {
        let bytes = try parseIPv4(value)
        data.replaceSubrange(offset..<(offset + 4), with: bytes.reversed())
    }

    private func parseIPv4(_ value: String) throws -> [UInt8] {
        let parts = value.split(separator: ".")
        guard parts.count == 4 else { throw AppError.message("Invalid IPv4 address: \(value)") }
        var bytes: [UInt8] = []
        for part in parts {
            guard let byte = UInt8(part) else { throw AppError.message("Invalid IPv4 address: \(value)") }
            bytes.append(byte)
        }
        return bytes
    }

    func removeSelectedPlaylistItem() {
        guard let selectedPlaylistItem else { return }
        playlistItems.removeAll { $0.id == selectedPlaylistItem }
        self.selectedPlaylistItem = nil
    }

    func chooseMessageFont(_ newFont: AppFont) {
        let token = "{\(newFont.markupToken)}"
        if hasActiveCanvasSelection {
            applyCanvasStyleToken(token)
        } else {
            font = newFont
        }
    }

    func chooseMessageColor(_ newColor: AppColor) {
        let token = "{\(newColor.markupToken)}"
        if hasActiveCanvasSelection {
            applyCanvasStyleToken(token)
        } else {
            color = newColor
        }
    }

    func chooseMessagePalette(_ newPalette: AppPalette) {
        let token: String
        switch newPalette {
        case .solid:
            token = "{\(color.markupToken)}"
        case .horizontalBands:
            token = "{bands}"
        case .characterStripes:
            token = "{characters}"
        case .diagonalDown:
            token = "{diagonal_down}"
        case .diagonalUp:
            token = "{diagonal_up}"
        }

        if hasActiveCanvasSelection {
            applyCanvasStyleToken(token)
        } else {
            palette = newPalette
        }
    }

    func applyCanvasStyleToken(_ token: String) {
        normalizeVisibleCanvasMarkupIfNeeded()
        let effectiveRange = activeCanvasSelectionRange
        if effectiveRange.length > 0 {
            canvasStyleRuns.removeAll { existing in
                existing.location == effectiveRange.location &&
                existing.length == effectiveRange.length &&
                Self.sameStyleTokenKind(existing.token, token)
            }
            canvasStyleRuns.append(CanvasStyleRun(location: effectiveRange.location, length: effectiveRange.length, token: token))
            selectedTextRange = NSRange(location: effectiveRange.location + effectiveRange.length, length: 0)
            lastCanvasSelectionRange = NSRange(location: 0, length: 0)
        } else {
            switch token.lowercased() {
            case "{red}":
                color = .red
                palette = .solid
            case "{green}":
                color = .green
                palette = .solid
            case "{orange}", "{yellow}":
                color = .orange
                palette = .solid
            case "{bands}":
                palette = .horizontalBands
            case "{characters}":
                palette = .characterStripes
            case "{diagonal_down}":
                palette = .diagonalDown
            case "{diagonal_up}":
                palette = .diagonalUp
            case "{font5}":
                font = .normal5
            case "{font7}":
                font = .normal7
            default:
                insertMessageToken(token)
            }
        }
    }

    private func normalizeVisibleCanvasMarkupIfNeeded() {
        let parsed = Self.parseVisibleMarkup(messageText)
        guard parsed.changed else { return }
        messageText = parsed.text
        canvasStyleRuns.append(contentsOf: parsed.styleRuns)
        selectedTextRange = NSRange(location: min(selectedTextRange.location, (messageText as NSString).length), length: 0)
        lastCanvasSelectionRange = NSRange(location: 0, length: 0)
    }

    func insertMessageToken(_ token: String) {
        // Only act on the CURRENT selection/cursor — never fall back to a stale selection.
        let nsText = messageText as NSString
        let currentRange: NSRange
        if selectedTextRange.length > 0,
           selectedTextRange.location >= 0,
           selectedTextRange.location + selectedTextRange.length <= nsText.length {
            currentRange = selectedTextRange
        } else {
            currentRange = NSRange(location: max(0, min(selectedTextRange.location, nsText.length)), length: 0)
        }

        if currentRange.length > 0 {
            // Replace the current selection with the token (no wrapping — tokens are atomic)
            messageText = nsText.replacingCharacters(in: currentRange, with: token)
            selectedTextRange = NSRange(location: currentRange.location + token.count, length: 0)
        } else {
            // Insert at cursor position
            let loc = currentRange.location
            let needsSpace = loc > 0 && loc <= nsText.length && nsText.character(at: loc - 1) > 32
            let prefix = needsSpace ? " " : ""
            messageText = nsText.replacingCharacters(in: NSRange(location: loc, length: 0), with: prefix + token)
            selectedTextRange = NSRange(location: loc + prefix.count + token.count, length: 0)
        }
        lastCanvasSelectionRange = NSRange(location: 0, length: 0)
    }

    func insertCountdown() {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: countdownTargetDate)
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let hour = components.hour else { return }
        let minute = components.minute ?? 0
        let second = components.second ?? 0

        let label = countdownLabel.isEmpty ? "Time Remaining" : countdownLabel
        let dir = countdownDirection == .up ? "up" : "down"

        // Marker format: {cd:month:day:year:hour:minute:second:direction:label}
        // The protocol layer (SigmaClient) expands this into the vendor prefix bytes.
        let marker = "{cd:\(month):\(day):\(year):\(hour):\(minute):\(second):\(dir):\(label)}"

        if !messageText.isEmpty && !messageText.hasSuffix("\n") {
            messageText += "\n"
        }
        messageText += marker
        selectedTextRange = NSRange(location: (messageText as NSString).length, length: 0)
    }

    private var hasActiveCanvasSelection: Bool {
        activeCanvasSelectionRange.length > 0
    }

    private var activeCanvasSelectionRange: NSRange {
        let textLength = (messageText as NSString).length
        if selectedTextRange.length > 0,
           selectedTextRange.location >= 0,
           selectedTextRange.location + selectedTextRange.length <= textLength {
            return selectedTextRange
        }
        if lastCanvasSelectionRange.length > 0,
           lastCanvasSelectionRange.location >= 0,
           lastCanvasSelectionRange.location + lastCanvasSelectionRange.length <= textLength {
            return lastCanvasSelectionRange
        }
        return NSRange(location: 0, length: 0)
    }

    private func restoreToken() -> String {
        switch palette {
        case .solid:
            switch color {
            case .red: return "{red}"
            case .green: return "{green}"
            case .orange: return "{orange}"
            }
        case .horizontalBands:
            return "{bands}"
        case .characterStripes:
            return "{characters}"
        case .diagonalDown:
            return "{diagonal_down}"
        case .diagonalUp:
            return "{diagonal_up}"
        }
    }

    private func restoreFontToken() -> String {
        "{\(font.markupToken)}"
    }

    nonisolated private static func sameStyleTokenKind(_ lhs: String, _ rhs: String) -> Bool {
        styleTokenKind(lhs) == styleTokenKind(rhs)
    }

    var selectedSerialPort: SerialPort? {
        guard let selectedSerialPortID else { return nil }
        return serialPorts.first { $0.id == selectedSerialPortID }
    }
}
