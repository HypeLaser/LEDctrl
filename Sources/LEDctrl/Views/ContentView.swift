import Foundation
import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var model = RescueModel()

    private let buildTimestamp: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy HH:mm"
        formatter.locale = Locale(identifier: "en_GB")
        return formatter.string(from: Date())
    }()

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $model.selectedSection) {
                    Label("Messages", systemImage: "text.bubble")
                        .tag(SectionID.messages)
                    Label("Headlines", systemImage: "newspaper")
                        .tag(SectionID.headlines)
                    Label("Progress Bar", systemImage: "chart.bar.fill")
                        .tag(SectionID.progressBar)
                    Label("Pixel Graphics", systemImage: "paintbrush")
                        .tag(SectionID.pixelGraphics)
                    Label("Convert", systemImage: "film.stack")
                        .tag(SectionID.convert)
                    Label("Playlists", systemImage: "music.note.list")
                        .tag(SectionID.playlists)
                    Label("Plex", systemImage: "play.tv")
                        .tag(SectionID.plex)
                    Label("Devices", systemImage: "cable.connector")
                        .tag(SectionID.devices)
                    Label("System Set", systemImage: "switch.2")
                        .tag(SectionID.systemSet)
                    Label("Network", systemImage: "network")
                        .tag(SectionID.network)
                    Label("Log", systemImage: "terminal")
                        .tag(SectionID.log)
                }
                .navigationTitle("LEDctrl")

                Divider()

                Text("v1.0 — \(buildTimestamp)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        } detail: {
            switch model.selectedSection {
            case .messages:
                MessagesView(model: model)
            case .headlines:
                HeadlinesView(model: model)
            case .progressBar:
                ProgressBarToolView(model: model)
            case .pixelGraphics:
                PixelGraphicsView(model: model)
            case .convert:
                ConvertView(model: model)
            case .playlists:
                PlaylistsView(model: model)
            case .plex:
                PlexView(model: model)
            case .devices:
                DevicesView(model: model)
            case .systemSet:
                SystemSetView(model: model)
            case .network:
                NetworkView(model: model)
            case .log:
                LogView(model: model)
            }
        }
        .task {
            model.refreshDevices()
        }
    }
}

private struct UserEntryFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(nsColor: .systemGray), lineWidth: 2)
                    .allowsHitTesting(false)
            )
    }
}

private extension View {
    func userEntryField() -> some View {
        modifier(UserEntryFieldModifier())
    }
}

struct DevicesView: View {
    @ObservedObject var model: RescueModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("USB serial")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    model.refreshDevices()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            Table(model.serialPorts, selection: $model.selectedSerialPortID) {
                TableColumn("Device") { port in
                    Text(port.path)
                }
                TableColumn("Hint") { port in
                    Text(port.hint)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 180)

            HStack(spacing: 12) {
                Picker("Baud", selection: $model.selectedBaud) {
                    ForEach([9600, 19200, 115200], id: \.self) { baud in
                        Text("\(baud)").tag(baud)
                    }
                }
                .frame(width: 180)

                TextField("Probe text", text: $model.serialProbeText)
                    .textFieldStyle(.roundedBorder)
                    .userEntryField()

                Button {
                    model.probeSelectedSerial()
                } label: {
                    Label("Probe Serial", systemImage: "paperplane")
                }
                .disabled(model.selectedSerialPort == nil)
            }

            Text("Detected from macOS: the likely panel path is /dev/cu.usbmodem11401 if it is still plugged in. The panel boot screen reports B1 9600 and B2 9600, so 9600 is the safest first serial probe.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .navigationTitle("Devices")
    }
}

struct NetworkView: View {
    @ObservedObject var model: RescueModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Network")
                .font(.title2.weight(.semibold))

            GroupBox("Known Sign") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        TextField("IP", text: $model.signIP)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .userEntryField()
                        TextField("Port", text: $model.signPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .userEntryField()
                        Button {
                            model.checkKnownSign()
                        } label: {
                            Label("Check", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                    HStack {
                        Label(model.netManagerStatus, systemImage: model.netManagerOK ? "checkmark.circle.fill" : "info.circle")
                            .foregroundStyle(model.netManagerOK ? .green : .secondary)
                        Spacer()
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("Probe Tools") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        TextField("IP address", text: $model.manualIP)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .userEntryField()
                        TextField("Port", text: $model.manualPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .userEntryField()
                        TextField("Probe text", text: $model.networkProbeText)
                            .textFieldStyle(.roundedBorder)
                            .userEntryField()
                        Button {
                            model.probeManualTCP()
                        } label: {
                            Label("Probe TCP", systemImage: "bolt.horizontal")
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            model.probeSigmaCandidates()
                        } label: {
                            Label("Probe Sigma Defaults", systemImage: "scope")
                        }
                        Button {
                            model.addLog("Candidate IPs: \(sigmaCandidateIPs.joined(separator: ", "))")
                            model.addLog("Candidate ports: \(sigmaCandidatePorts.map(String.init).joined(separator: ", "))")
                        } label: {
                            Label("Show Defaults", systemImage: "list.bullet")
                        }
                        Spacer()
                    }
                }
                .padding(.top, 4)
            }

            Table(model.probeResults) {
                TableColumn("Target") { result in
                    Text(result.target)
                }
                TableColumn("Status") { result in
                    Text(result.status)
                }
                TableColumn("Response") { result in
                    Text(result.response)
                        .lineLimit(1)
                }
            }

            Text("Panel is now configured on your LAN at \(model.signIP). Original boot/default address was 192.168.0.19; width 80, height 7, LED BIN-A, version A512GGUU 0101.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Network")
    }
}

struct PlexView: View {
    @ObservedObject var model: RescueModel

    private var previewText: String {
        guard !model.plexNowPlaying.isEmpty else { return "Nothing playing" }
        let item = model.plexNowPlaying[0]
        return model.plexFormatTemplate
            .replacingOccurrences(of: "{title}", with: item.displayTitle)
            .replacingOccurrences(of: "{user}", with: item.user)
            .replacingOccurrences(of: "{type}", with: item.type)
            .replacingOccurrences(of: "{progress}", with: "\(item.progressPercent)%")
            .replacingOccurrences(of: "{remaining}", with: item.timeRemainingFormatted)
            .replacingOccurrences(of: "{endtime}", with: item.endTimeFormatted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Plex Now Playing")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    model.refreshPlexNowPlaying()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isSending)
            }

            GroupBox("Preview") {
                LEDPixelCanvas(
                    text: previewText,
                    font: model.plexFont,
                    color: model.plexColor.previewColor,
                    palette: model.plexPalette
                )
                .frame(maxWidth: .infinity, maxHeight: 70)
            }

            GroupBox("Server") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text("URL")
                            .frame(width: 50, alignment: .trailing)
                        TextField("http://192.168.11.22:32400", text: $model.plexServerURL)
                            .textFieldStyle(.roundedBorder)
                            .userEntryField()
                    }
                    HStack(spacing: 10) {
                        Text("Token")
                            .frame(width: 50, alignment: .trailing)
                        SecureField("Plex token", text: $model.plexToken)
                            .textFieldStyle(.roundedBorder)
                            .userEntryField()
                    }
                    HStack(spacing: 10) {
                        Text("Format")
                            .frame(width: 50, alignment: .trailing)
                        TextField("Now Watching: {title}", text: $model.plexFormatTemplate)
                            .textFieldStyle(.roundedBorder)
                            .userEntryField()
                    }
                    HStack(spacing: 16) {
                        Toggle("Auto-refresh (5s)", isOn: $model.plexAutoRefresh)
                            .toggleStyle(.checkbox)
                            .onChange(of: model.plexAutoRefresh) { oldValue, newValue in
                                if newValue {
                                    model.startPlexAutoRefresh()
                                } else {
                                    model.stopPlexAutoRefresh()
                                }
                            }
                        Toggle("Auto-send to sign", isOn: $model.plexAutoSend)
                            .toggleStyle(.checkbox)
                        Spacer()
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("Style") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Font", selection: $model.plexFont) {
                        ForEach(AppFont.allCases) { font in
                            Text(font.label).tag(font)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)

                    HStack(spacing: 8) {
                        Text("Brush")
                            .foregroundStyle(.secondary)
                        ForEach([AppColor.red, .orange, .green], id: \.self) { color in
                            Button {
                                model.plexColor = color
                            } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(color.previewColor)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(
                                                model.plexColor == color
                                                    ? Color.white
                                                    : Color(nsColor: .separatorColor),
                                                lineWidth: model.plexColor == color ? 2 : 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }

                    Picker("Palette", selection: $model.plexPalette) {
                        ForEach(AppPalette.allCases) { palette in
                            Text(palette.label).tag(palette)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 380)
                }
                .padding(.top, 4)
            }

            GroupBox("Now Playing") {
                if model.plexNowPlaying.isEmpty {
                    Text(model.plexStatus)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.plexNowPlaying) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayTitle)
                                        .font(.system(.body, design: .monospaced).weight(.semibold))
                                    Text("\(item.user) — \(item.state) — \(item.progressPercent)% — \(item.timeRemainingFormatted) left — ends ~\(item.endTimeFormatted)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            if item.id != model.plexNowPlaying.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    model.sendPlexNowPlayingToSign()
                } label: {
                    Label(model.isSending ? "Sending" : "Send to Sign", systemImage: "paperplane.fill")
                }
                .controlSize(.large)
                .disabled(model.isSending || model.plexNowPlaying.isEmpty)

                if !model.plexLastSentText.isEmpty {
                    Text("Last: \(model.plexLastSentText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            Text("Format tokens: {title} {user} {type} {progress} {remaining} {endtime}")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(model.plexStatus, systemImage: model.lastSendSucceeded ? "checkmark.circle.fill" : "info.circle")
                .foregroundStyle(model.lastSendSucceeded ? .green : .secondary)

            Spacer()
        }
        .padding()
        .navigationTitle("Plex")
        .onAppear {
            if model.plexAutoRefresh {
                model.startPlexAutoRefresh()
            }
        }
        .onDisappear {
            model.stopPlexAutoRefresh()
        }
    }
}

struct MessagesView: View {
    @ObservedObject var model: RescueModel

    private let canvasViewportWidth: CGFloat = 520
    private let canvasViewportHeight: CGFloat = 650

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            controlColumn
                .frame(width: 295)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("80 x 7 Canvas", systemImage: "rectangle.dashed")
                        .font(.headline)
                    Spacer()
                    Text("Panel width: 80")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                PixelCanvasEditor(
                    text: $model.messageText,
                    styleRuns: $model.canvasStyleRuns,
                    rowAlignments: model.canvasRowAlignments,
                    font: model.font,
                    baseColor: model.color,
                    basePalette: model.palette,
                    selection: $model.selectedTextRange,
                    onSelectionChange: { range in
                        model.updateCanvasSelection(range: range)
                    }
                )
                .frame(width: canvasViewportWidth, height: canvasViewportHeight)
                .background(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color(nsColor: .systemGray), lineWidth: 2)
                        .allowsHitTesting(false)
                )

                HStack {
                    Text("Lines: \(model.canvasLineCount)/7")
                    Divider()
                        .frame(height: 18)
                    Text("Height: 7")
                    Spacer()
                    Text("\(model.messageMode.label) | \(model.font.label)")
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

                Label("Sign Preview", systemImage: "display")
                    .font(.headline)
                    .padding(.top, 8)
                LEDSignEmulator(
                    text: model.messageText,
                    styleRuns: model.canvasStyleRuns,
                    font: model.font,
                    color: model.color.previewColor,
                    palette: model.palette,
                    mode: model.messageMode,
                    inMode: model.inMode,
                    outMode: model.outMode,
                    speed: model.speed,
                    holdSeconds: model.pauseSeconds,
                    restartSeed: model.previewRestartSeed
                )
                .frame(width: canvasViewportWidth, height: 55)

                Label(model.messageStatus, systemImage: model.lastSendSucceeded ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(model.lastSendSucceeded ? .green : .secondary)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle("Messages")
        .onChange(of: model.inMode) { model.restartPreviewAnimation() }
        .onChange(of: model.outMode) { model.restartPreviewAnimation() }
        .onChange(of: model.speed) { model.restartPreviewAnimation() }
        .onChange(of: model.pauseSeconds) { model.restartPreviewAnimation() }
        .onChange(of: model.messageMode) { model.restartPreviewAnimation() }
    }

    private var controlColumn: some View {
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    model.sendCurrentMessage()
                } label: {
                    Label(model.isSending ? "Sending" : "Send", systemImage: "paperplane.fill")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .controlSize(.large)
                .disabled(model.isSending || model.normalizedMessageText.isEmpty)

                Button {
                    model.probeSignStatus()
                } label: {
                    Label("Probe", systemImage: "waveform.path.ecg")
                }
                .disabled(model.isSending)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Mode", selection: $model.messageMode) {
                    ForEach(MessageMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Send rows separately", isOn: $model.messageRowsSeparate)
                    .toggleStyle(.checkbox)
                    .disabled(true)
                    .help("Not yet available — needs firmware sequence-file capture to verify safe multi-program delivery.")

                GroupBox("Style") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Font", selection: Binding(
                            get: { model.font },
                            set: { model.chooseMessageFont($0) }
                        )) {
                            ForEach(AppFont.allCases) { font in
                                Text(font.label).tag(font)
                            }
                        }

                        HStack(spacing: 8) {
                            Text("Brush")
                                .foregroundStyle(.secondary)
                            ForEach([AppColor.red, .orange, .green], id: \.self) { color in
                                Button {
                                    model.chooseMessageColor(color)
                                } label: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(color.previewColor)
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(
                                                    model.color == color
                                                        ? Color.white
                                                        : Color(nsColor: .separatorColor),
                                                    lineWidth: model.color == color ? 2 : 1
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(color.label)
                            }
                        }

                        Picker("Palette", selection: Binding(
                            get: { model.palette },
                            set: { model.chooseMessagePalette($0) }
                        )) {
                            ForEach(AppPalette.allCases) { palette in
                                Text(palette.label).tag(palette)
                            }
                        }

                        Picker("Send Profile", selection: $model.senderProfile) {
                            ForEach(SenderProfile.allCases) { profile in
                                Text(profile.label).tag(profile)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("`Editor Font` uses Editor-style font selector bytes while keeping the stable sender path.")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Motion") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("In", selection: $model.inMode) {
                            ForEach(SigmaEffect.all) { effect in
                                Text(effect.name).tag(effect)
                            }
                        }
                        .disabled(model.messageMode == .marquee)

                        Picker("Out", selection: $model.outMode) {
                            ForEach(SigmaEffect.all) { effect in
                                Text(effect.name).tag(effect)
                            }
                        }
                        .disabled(model.messageMode == .marquee)

                        HStack(alignment: .center, spacing: 10) {
                            Picker("Speed", selection: $model.speed) {
                                ForEach(SigmaSpeed.allCases) { speed in
                                    Text(speed.label).tag(speed)
                                }
                            }
                            Stepper("Hold \(model.pauseSeconds)s", value: $model.pauseSeconds, in: 0...120)
                        }

                        if model.messageMode == .marquee {
                            Text("Marquee mode sends Move Left for both In and Out.")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("IN/OUT Preview")
                        .font(.headline)
                    LEDSignEmulator(
                        text: "EFFECT DEMO",
                        styleRuns: [],
                        font: .normal7,
                        color: model.color.previewColor,
                        palette: .solid,
                        mode: .fitted,
                        inMode: model.inMode,
                        outMode: model.outMode,
                        speed: model.speed,
                        holdSeconds: 1,
                        restartSeed: model.previewRestartSeed
                    )
                    .frame(height: 30)
                    HStack(spacing: 8) {
                        Text("In: \(model.inMode.name)")
                        Text("Out: \(model.outMode.name)")
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    Button("Restart Preview") {
                        model.restartPreviewAnimation()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                Picker("Alignment", selection: Binding(
                    get: { model.activeCanvasAlignment },
                    set: { model.setActiveCanvasAlignment($0) }
                )) {
                    ForEach(CanvasAlignment.allCases) { alignment in
                        Text(alignment.label).tag(alignment)
                    }
                }
                .pickerStyle(.segmented)

                Divider()

                Text("Insert")
                    .font(.headline)
                toolButton("Hour") { model.insertMessageToken("{hour}") }
                toolButton("Minute") { model.insertMessageToken("{minute}") }
                toolButton("Second") { model.insertMessageToken("{second}") }
                toolButton("HH:MM") { model.insertMessageToken("{hhmm24}") }
                toolButton("HH:MM AM/PM") { model.insertMessageToken("{hhmm12}") }
                toolButton("Day") { model.insertMessageToken("{day_name}") }
                toolButton("Day No.") { model.insertMessageToken("{day_ordinal}") }
                toolButton("Month") { model.insertMessageToken("{month_name}") }
                toolButton("Full Date") { model.insertMessageToken("{date_long}") }
                toolButton("DD/MM/YY") { model.insertMessageToken("{date_short_uk}") }

                Divider()

                Text("Countdown")
                    .font(.headline)
                DatePicker("Target", selection: $model.countdownTargetDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                TextField("Label", text: $model.countdownLabel)
                    .userEntryField()
                Picker("Direction", selection: $model.countdownDirection) {
                    ForEach(RescueModel.CountdownDirection.allCases) { direction in
                        Text(direction.label).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
                Button("Insert Countdown Row") {
                    model.insertCountdown()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(model.messageLog.suffix(8).joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .buttonStyle(.bordered)
        }
    }
    }

    private func toolButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MessageCanvasRowView: View {
    @Binding var row: MessageRow
    let isSelected: Bool
    let onSelect: () -> Void
    let onSelectionChange: (NSRange) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("Row \(row.order + 1)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .frame(width: 52, alignment: .leading)
                NativeRowTextEditor(
                    text: $row.text,
                    placeholder: "Message row",
                    onFocus: onSelect,
                    onSelectionChange: onSelectionChange
                )
                    .userEntryField()
                    .frame(height: 34)
                Button {
                    onSelect()
                } label: {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                }
                .buttonStyle(.plain)
                .help("Edit this row's controls")
            }

            Text("\(row.mode.label) | \(row.font.label) | base \(row.color.label) / \(row.palette.label) | \(row.speed.label) | hold \(row.pauseSeconds)s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(isSelected ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.14) : Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

struct HeadlinesView: View {
    @ObservedObject var model: RescueModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Picker("Send lines as", selection: $model.headlineMode) {
                    ForEach(HeadlineMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Button {
                    model.sendHeadlineLines()
                } label: {
                    Label(model.isSending ? "Sending" : "Send Headlines", systemImage: "list.bullet.rectangle.portrait")
                }
                .controlSize(.large)
                .disabled(model.isSending || model.headlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }

            HStack(spacing: 10) {
                Picker("Font", selection: $model.font) {
                    ForEach(AppFont.allCases) { font in
                        Text("\(font.label) - \(font.maxCharactersPerLine) chars").tag(font)
                    }
                }
                .frame(width: 230)

                Picker("Color", selection: $model.color) {
                    ForEach(AppColor.allCases) { color in
                        Text(color.label).tag(color)
                    }
                }
                .frame(width: 140)

                Picker("Speed", selection: $model.speed) {
                    ForEach(SigmaSpeed.allCases) { speed in
                        Text(speed.label).tag(speed)
                    }
                }

                Stepper("Hold \(model.pauseSeconds)s", value: $model.pauseSeconds, in: 0...120)
                    .frame(width: 160)

                Button {
                    model.loadProjectHeadlines()
                } label: {
                    Label("Load Project File", systemImage: "doc.text")
                }

                Button {
                    model.chooseHeadlineFile()
                } label: {
                    Label("Choose File", systemImage: "folder")
                }
            }

            NativeMultilineField(text: $model.headlineText, placeholder: "One headline per line")
                .frame(minHeight: 180)
                .userEntryField()

            VStack(alignment: .leading, spacing: 8) {
                Label("First Line Preview", systemImage: "display")
                    .font(.headline)
                LEDPixelCanvas(text: model.firstHeadlinePreview, font: model.font, color: model.color.previewColor)
                    .frame(maxWidth: .infinity)
                Text("\(model.headlineLineCount) line(s) | \(model.headlineMode.label) | unsupported punctuation is normalized before sending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label(model.messageStatus, systemImage: model.lastSendSucceeded ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(model.lastSendSucceeded ? .green : .secondary)
                Spacer()
            }

            Divider()

            ScrollView {
                Text(model.messageLog.joined(separator: "\n"))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 120)
        }
        .padding()
        .navigationTitle("Headlines")
    }
}

struct ProgressBarToolView: View {
    @ObservedObject var model: RescueModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Progress Bar")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    model.probeSignStatus()
                } label: {
                    Label("Probe", systemImage: "waveform.path.ecg")
                }
                .disabled(model.isSending)
            }

            HStack(spacing: 14) {
                Stepper("Duration \(model.progressDurationSeconds)s", value: $model.progressDurationSeconds, in: 1...300)
                    .frame(width: 190)
                Stepper("Frames \(model.progressFrameCount)", value: $model.progressFrameCount, in: 2...40)
                    .frame(width: 150)
                Picker("Color", selection: $model.progressColor) {
                    ForEach(AppColor.allCases) { color in
                        Text(color.label).tag(color)
                    }
                }
                .frame(width: 140)
                Toggle("Show percent", isOn: $model.progressShowsPercent)
                    .toggleStyle(.checkbox)
                    .frame(width: 130)
                Toggle("Stop after one cycle", isOn: $model.progressStopAfterOneCycle)
                    .toggleStyle(.checkbox)
                    .frame(width: 190)
                Picker("Speed", selection: $model.speed) {
                    ForEach(SigmaSpeed.allCases) { speed in
                        Text(speed.label).tag(speed)
                    }
                }
                .frame(width: 140)
                Picker("Engine", selection: $model.progressSendEngine) {
                    ForEach(ProgressSendEngine.allCases) { engine in
                        Text(engine.label).tag(engine)
                    }
                }
                .frame(width: 170)
                Spacer()
            }

            LEDPixelCanvas(
                rendered: model.progressPreviewFrame,
                color: model.progressColor.previewColor,
                showsBorder: true
            )
            .frame(maxWidth: .infinity, maxHeight: 70)

            HStack(spacing: 12) {
                Button {
                    model.sendProgressBar(fill: 0)
                } label: {
                    Label("Send Empty", systemImage: "circle")
                }
                .disabled(model.isSending)

                Button {
                    model.sendProgressBar(fill: 0.5)
                } label: {
                    Label("Send Half", systemImage: "circle.lefthalf.filled")
                }
                .disabled(model.isSending)

                Button {
                    model.sendProgressAnimation()
                } label: {
                    Label(model.isSending ? "Running" : "Start Timer", systemImage: "play.fill")
                }
                .keyboardShortcut("p", modifiers: [.command])
                .controlSize(.large)
                .disabled(model.isSending)

                Button {
                    model.sendProgressBar(fill: 1)
                } label: {
                    Label("Send Full", systemImage: "checkmark.circle.fill")
                }
                .disabled(model.isSending)

                Spacer()
            }

            Text("Progress engine: \(model.progressSendEngine.label). Text is reliable; Bitmap Editor Program is for controlled retrace testing.")
                .foregroundStyle(.secondary)

            HStack {
                Label(model.progressStatus, systemImage: model.lastSendSucceeded ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(model.lastSendSucceeded ? .green : .secondary)
                Spacer()
            }

            ScrollView {
                Text(model.messageLog.joined(separator: "\n"))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 160)
        }
        .padding()
        .navigationTitle("Progress Bar")
    }
}

struct PixelGraphicsView: View {
    @ObservedObject var model: RescueModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Pixel Graphics")
                    .font(.title2.weight(.semibold))
                Spacer()
            }

            GroupBox("Pixel Graphics (80x7)") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Text("Brush")
                                .foregroundStyle(.secondary)
                            ForEach([GraphicsBrush.red, .orange, .green], id: \.self) { brush in
                                Button {
                                    model.graphicsBrush = brush
                                } label: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(brush.swatchColor)
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(
                                                    model.graphicsBrush == brush
                                                        ? Color.white
                                                        : Color(nsColor: .separatorColor),
                                                    lineWidth: model.graphicsBrush == brush ? 2 : 1
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(brush.label)
                            }
                            Button {
                                model.graphicsBrush = .erase
                            } label: {
                                Label("Erase", systemImage: "eraser")
                            }
                            .buttonStyle(.borderless)
                        }

                        Button("Clear") { model.clearGraphicsPixels() }
                            .disabled(model.isSending)
                        Button("Checker") { model.checkerGraphicsPreset() }
                            .disabled(model.isSending)
                        Button("Chevron") { model.chevronGraphicsPreset() }
                            .disabled(model.isSending)
                        Button {
                            model.saveGraphicsPNG()
                        } label: {
                            Label("Save PNG", systemImage: "square.and.arrow.down")
                        }
                        .disabled(model.isSending)
                        Button {
                            model.loadGraphicsPNG()
                        } label: {
                            Label("Load PNG", systemImage: "square.and.arrow.up")
                        }
                        .disabled(model.isSending)
                        Button {
                            model.sendGraphicsBackgroundFrame()
                        } label: {
                            Label("Set Background (Canvas)", systemImage: "photo.fill")
                        }
                        .disabled(model.isSending)
                        Button {
                            model.sendForegroundTextOnly()
                        } label: {
                            Label("Send Foreground Text", systemImage: "text.bubble.fill")
                        }
                        .disabled(model.isSending || model.normalizedMessageText.isEmpty)
                        Button {
                            model.replayEditorRowChange120Capture()
                        } label: {
                            Label("Replay 120ms Capture", systemImage: "bolt.fill")
                        }
                        .disabled(model.isSending)
                        Spacer()
                        Button {
                            model.sendGraphicsFrame()
                        } label: {
                            Label("Send Graphic (Legacy)", systemImage: "square.and.arrow.up")
                        }
                        .disabled(model.isSending)
                    }

                    HStack(spacing: 12) {
                        Picker("Foreground Speed", selection: $model.foregroundOverlaySpeed) {
                            ForEach(SigmaSpeed.allCases) { speed in
                                Text(speed.label).tag(speed)
                            }
                        }
                        .frame(width: 180)

                        Toggle("Use 120ms Capture Timing", isOn: $model.foregroundOverlayUseCaptureTiming)
                            .toggleStyle(.checkbox)
                            .frame(width: 210)

                        Stepper(
                            String(
                                format: "Timing Code 0x%02X (%d)",
                                model.foregroundOverlayTimingCode,
                                model.foregroundOverlayTimingCode
                            ),
                            value: $model.foregroundOverlayTimingCode,
                            in: 1...255
                        )
                        .frame(width: 240)
                        .disabled(model.foregroundOverlayUseCaptureTiming)
                        Spacer()
                    }

                    PixelGraphicsEditor(model: model)
                        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 160)

                    HStack {
                        Label(model.graphicsStatus, systemImage: model.lastSendSucceeded ? "checkmark.circle.fill" : "info.circle")
                            .foregroundStyle(model.lastSendSucceeded ? .green : .secondary)
                        Spacer()
                    }
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Pixel Graphics")
    }
}

struct ConvertView: View {
    @ObservedObject var model: RescueModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Convert")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    model.sendConvertedMovieToSign()
                } label: {
                    Label("Send Last Movie", systemImage: "paperplane.fill")
                }
                .disabled(model.isSending || model.convertLastFLWPath.isEmpty)
            }

            GroupBox("Source") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Input Type", selection: $model.convertSourceMode) {
                        Text("Video File").tag(ConvertSourceMode.videoFile)
                        Text("PNG Sequence").tag(ConvertSourceMode.pngSequenceFolder)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)

                    HStack(spacing: 10) {
                        TextField(model.convertSourceMode == .videoFile ? "Video path" : "PNG folder path", text: $model.convertSourcePath)
                            .textFieldStyle(.roundedBorder)
                            .userEntryField()
                        Button {
                            model.chooseConvertSource()
                        } label: {
                            Label("Browse", systemImage: "folder")
                        }
                    }

                    if model.convertSourceMode == .pngSequenceFolder {
                        HStack(spacing: 10) {
                            TextField("Pattern (e.g. frame-*.png)", text: $model.convertSequencePattern)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 260)
                                .userEntryField()
                            Text("Pattern is matched inside the selected folder.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("Output") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Stepper("Width \(model.convertTargetWidth)", value: $model.convertTargetWidth, in: 8...512)
                            .frame(width: 150)
                        Stepper("Height \(model.convertTargetHeight)", value: $model.convertTargetHeight, in: 7...256)
                            .frame(width: 150)
                        Stepper("FPS \(model.convertFPS)", value: $model.convertFPS, in: 1...60)
                            .frame(width: 140)
                        TextField("Base filename", text: $model.convertBaseName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .userEntryField()
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        TextField("Output folder", text: $model.convertOutputDirectory)
                            .textFieldStyle(.roundedBorder)
                            .userEntryField()
                        Button {
                            model.chooseConvertOutputFolder()
                        } label: {
                            Label("Choose Folder", systemImage: "folder.badge.plus")
                        }
                    }
                }
                .padding(.top, 4)
            }

            HStack(spacing: 12) {
                Button {
                    model.convertMediaToSignMovie()
                } label: {
                    Label(model.isSending ? "Converting" : "Convert To FLW", systemImage: "film")
                }
                .controlSize(.large)
                .disabled(model.isSending)

                if !model.convertLastFLVPath.isEmpty {
                    Text("FLV: \(URL(fileURLWithPath: model.convertLastFLVPath).lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !model.convertLastFLWPath.isEmpty {
                    Text("FLW: \(URL(fileURLWithPath: model.convertLastFLWPath).lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack {
                Label(model.convertStatus, systemImage: model.lastSendSucceeded ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(model.lastSendSucceeded ? .green : .secondary)
                Spacer()
            }

            Divider()

            ScrollView {
                Text(model.messageLog.joined(separator: "\n"))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 170)
        }
        .padding()
        .navigationTitle("Convert")
    }
}

struct PixelGraphicsEditor: View {
    @ObservedObject var model: RescueModel

    private let columns = 80
    private let rows = 7

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 1
            let cell = max(3, min((proxy.size.width - CGFloat(columns - 1) * gap) / CGFloat(columns),
                                  (proxy.size.height - CGFloat(rows - 1) * gap) / CGFloat(rows)))
            let gridWidth = CGFloat(columns) * cell + CGFloat(columns - 1) * gap
            let gridHeight = CGFloat(rows) * cell + CGFloat(rows - 1) * gap
            let origin = CGPoint(x: (proxy.size.width - gridWidth) / 2, y: (proxy.size.height - gridHeight) / 2)

            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                for y in 0..<rows {
                    for x in 0..<columns {
                        let pixel = model.graphicsPixels[y * columns + x]
                        let color: Color
                        switch pixel {
                        case .off:
                            color = Color(red: 0.04, green: 0.06, blue: 0.05)
                        case .red:
                            color = .red
                        case .green:
                            color = .green
                        case .orange:
                            color = .orange
                        }
                        let rect = CGRect(
                            x: origin.x + CGFloat(x) * (cell + gap),
                            y: origin.y + CGFloat(y) * (cell + gap),
                            width: cell,
                            height: cell
                        )
                        context.fill(Path(roundedRect: rect, cornerRadius: max(0.4, cell * 0.12)), with: .color(color))
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(nsColor: .systemGray), lineWidth: 2)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let step = cell + gap
                        let px = Int((value.location.x - origin.x) / step)
                        let py = Int((value.location.y - origin.y) / step)
                        model.paintGraphicsPixel(x: px, y: py)
                    }
            )
        }
        .background(Color.black)
    }
}

struct LEDSignEmulator: View {
    let text: String
    let styleRuns: [CanvasStyleRun]
    let font: AppFont
    let color: Color
    let palette: AppPalette
    let mode: MessageMode
    let inMode: SigmaEffect
    let outMode: SigmaEffect
    let speed: SigmaSpeed
    let holdSeconds: Int
    let restartSeed: TimeInterval
    var usesEffectPhases = true

    var body: some View {
        TimelineView(.animation) { timeline in
            let frame = previewFrame(at: timeline.date)
            LEDPixelCanvas(
                text: frame.text,
                styleRuns: frame.styleRuns,
                font: font,
                color: color,
                palette: palette,
                xOffset: frame.xOffset,
                yOffset: frame.yOffset
            )
        }
    }

    private func previewFrame(at date: Date) -> (text: String, styleRuns: [CanvasStyleRun], xOffset: Int, yOffset: Int) {
        let lines = styledLines()
        guard !lines.isEmpty else { return ("", [], 0, 0) }
        if mode == .marquee {
            return marqueeFrame(lines: lines, at: date)
        }

        let elapsed = date.timeIntervalSinceReferenceDate - restartSeed
        let hold = max(0.05, Double(holdSeconds))
        let index = min(lines.count - 1, Int(elapsed / hold) % lines.count)
        let line = lines[index]
        let offset = usesEffectPhases
            ? phasedEffectOffset(for: line, elapsed: elapsed)
            : legacyPreviewOffset(for: line, at: date)
        return (line.text, line.styleRuns, offset.x, offset.y)
    }

    private func marqueeFrame(lines: [(text: String, styleRuns: [CanvasStyleRun])], at date: Date) -> (text: String, styleRuns: [CanvasStyleRun], xOffset: Int, yOffset: Int) {
        let elapsed = date.timeIntervalSinceReferenceDate - restartSeed
        let hardwarePixelsPerSecond = speed.previewPixelsPerSecond
        var cursor = 0.0

        for line in lines {
            let width = PixelFontRenderer.textWidth(line.text, baseStyle: font, styleRuns: line.styleRuns)
            let travel = max(1, width + 86)
            let moveDuration = Double(travel) / hardwarePixelsPerSecond
            let restartGap = max(0.0, Double(holdSeconds))
            let duration = moveDuration + restartGap
            if elapsed.truncatingRemainder(dividingBy: totalMarqueeDuration(lines: lines)) < cursor + duration {
                let local = elapsed.truncatingRemainder(dividingBy: totalMarqueeDuration(lines: lines)) - cursor
                if local >= moveDuration {
                    return (line.text, line.styleRuns, -(width + 6), 0)
                }
                return (line.text, line.styleRuns, 80 - Int(local * hardwarePixelsPerSecond), 0)
            }
            cursor += duration
        }

        let first = lines[0]
        return (first.text, first.styleRuns, 80, 0)
    }

    private func totalMarqueeDuration(lines: [(text: String, styleRuns: [CanvasStyleRun])]) -> Double {
        lines.reduce(0) { total, line in
            let width = PixelFontRenderer.textWidth(line.text, baseStyle: font, styleRuns: line.styleRuns)
            let moveDuration = Double(width + 86) / speed.previewPixelsPerSecond
            return total + moveDuration + max(0.0, Double(holdSeconds))
        }
    }

    private func phasedEffectOffset(for line: (text: String, styleRuns: [CanvasStyleRun]), elapsed: TimeInterval) -> (x: Int, y: Int) {
        let width = PixelFontRenderer.textWidth(line.text, baseStyle: font, styleRuns: line.styleRuns)
        guard width > 0 else { return (0, 0) }
        let centered = max(0, (80 - width) / 2)
        let enterDuration = max(0.35, 80.0 / speed.previewPixelsPerSecond)
        let exitDuration = enterDuration
        let hold = max(0.0, Double(holdSeconds))
        let gap = 0.25
        let cycle = enterDuration + hold + exitDuration + gap
        let phase = elapsed.truncatingRemainder(dividingBy: cycle)

        if phase < enterDuration {
            return offset(for: inMode, width: width, centered: centered, progress: phase / enterDuration, entering: true)
        }
        if phase < enterDuration + hold {
            return (centered, 0)
        }
        if phase < enterDuration + hold + exitDuration {
            let local = (phase - enterDuration - hold) / exitDuration
            return offset(for: outMode, width: width, centered: centered, progress: local, entering: false)
        }
        return (centered, 0)
    }

    private func offset(for effect: SigmaEffect, width: Int, centered: Int, progress: Double, entering: Bool) -> (x: Int, y: Int) {
        let p = max(0, min(1, progress))
        let name = effect.name.lowercased()

        func lerp(_ start: Double, _ end: Double) -> Int {
            Int((start + (end - start) * p).rounded())
        }

        if name.contains("left") || name.contains("scroll o/l") {
            return entering
                ? (lerp(80, Double(centered)), 0)
                : (lerp(Double(centered), Double(-width - 1)), 0)
        }

        if name.contains("right") || name.contains("scroll o/r") {
            return entering
                ? (lerp(Double(-width - 1), Double(centered)), 0)
                : (lerp(Double(centered), 80), 0)
        }

        if name.contains("up") {
            return entering
                ? (centered, lerp(7, 0))
                : (centered, lerp(0, -7))
        }

        if name.contains("down") {
            return entering
                ? (centered, lerp(-7, 0))
                : (centered, lerp(0, 7))
        }

        if name.contains("scroll to l/r") || name.contains("fold from l/r") || name.contains("shuttle from l/r") {
            return entering
                ? (lerp(80, Double(centered)), 0)
                : (lerp(Double(centered), Double(-width - 1)), 0)
        }

        if name.contains("scroll to u/d") || name.contains("fold from u/d") || name.contains("shuttle from u/d") || name.contains("scroll o/c") {
            return entering
                ? (centered, lerp(7, 0))
                : (centered, lerp(0, -7))
        }

        return (centered, 0)
    }

    private func legacyPreviewOffset(for line: (text: String, styleRuns: [CanvasStyleRun]), at date: Date) -> (x: Int, y: Int) {
        let width = PixelFontRenderer.textWidth(line.text, baseStyle: font, styleRuns: line.styleRuns)
        guard width > 0 else { return (0, 0) }
        let elapsed = date.timeIntervalSinceReferenceDate - restartSeed
        let hardwarePixelsPerSecond = speed.previewPixelsPerSecond
        let centered = max(0, (80 - width) / 2)

        if mode == .marquee {
            let travel = width + 86
            let moveDuration = Double(travel) / hardwarePixelsPerSecond
            let restartGap = max(0.0, Double(holdSeconds))
            let cycle = max(0.1, moveDuration + restartGap)
            let phase = elapsed.truncatingRemainder(dividingBy: cycle)
            if phase >= moveDuration {
                return (-(width + 6), 0)
            }
            let position = Int(phase * hardwarePixelsPerSecond)
            return (80 - position, 0)
        }

        if inMode.name.lowercased().contains("move left") || inMode.name.lowercased().contains("scroll left") {
            let travel = width + 86
            let moveDuration = Double(travel) / hardwarePixelsPerSecond
            let restartGap = max(0.0, Double(holdSeconds))
            let cycle = max(0.1, moveDuration + restartGap)
            let phase = elapsed.truncatingRemainder(dividingBy: cycle)
            if phase >= moveDuration {
                return (-(width + 6), 0)
            }
            let position = Int(phase * hardwarePixelsPerSecond)
            return (80 - position, 0)
        }

        if inMode.name.lowercased().contains("move right") || inMode.name.lowercased().contains("scroll right") {
            let period = 4.0
            let progress = min(1.0, (elapsed.truncatingRemainder(dividingBy: period)) / 1.4)
            return (-Int((1.0 - progress) * Double(width + 6)), 0)
        }

        if inMode.name.lowercased().contains("move up") || inMode.name.lowercased().contains("scroll up") {
            let period = 3.0
            let progress = min(1.0, (elapsed.truncatingRemainder(dividingBy: period)) / 1.2)
            return (centered, 7 - Int(progress * 7.0))
        }

        if inMode.name.lowercased().contains("move down") || inMode.name.lowercased().contains("scroll down") {
            let period = 3.0
            let progress = min(1.0, (elapsed.truncatingRemainder(dividingBy: period)) / 1.2)
            return (centered, -7 + Int(progress * 7.0))
        }

        return (centered, 0)
    }

    private func styledLines() -> [(text: String, styleRuns: [CanvasStyleRun])] {
        let displayText = RescueModel.displayTextForCanvas(text)
        let nsText = displayText as NSString
        let lineRanges = nsText.lineRanges
        return lineRanges.compactMap { lineRange in
            var contentRange = lineRange
            while contentRange.length > 0 {
                let last = nsText.character(at: contentRange.location + contentRange.length - 1)
                if last == 10 || last == 13 {
                    contentRange.length -= 1
                } else {
                    break
                }
            }
            let rawLineText = nsText.substring(with: contentRange)
            let lineText = rawLineText.trimmingCharacters(in: .whitespaces)
            guard !lineText.isEmpty else { return nil }
            let trimmedPrefix = rawLineText.count - rawLineText.trimmingCharacters(in: .whitespacesAndNewlines).count
            let contentStart = contentRange.location + max(0, trimmedPrefix)
            let runs = styleRuns.compactMap { run -> CanvasStyleRun? in
                let intersectionStart = max(run.location, contentStart)
                let intersectionEnd = min(run.location + run.length, contentStart + (lineText as NSString).length)
                guard intersectionEnd > intersectionStart else { return nil }
                return CanvasStyleRun(
                    location: intersectionStart - contentStart,
                    length: intersectionEnd - intersectionStart,
                    token: run.token
                )
            }
            return (lineText, runs)
        }
    }
}

struct LEDPixelCanvas: View {
    var text: String = ""
    var rendered: PixelFontRenderer.RenderedPixels?
    var styleRuns: [CanvasStyleRun] = []
    var font: AppFont = .normal7
    let color: Color
    var palette: AppPalette = .solid
    var xOffset: Int = 0
    var yOffset: Int = 0
    var showsBorder = true
    var columns = 80

    private let rows = 7

    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 1
            let cell = max(2, min((size.width - CGFloat(columns - 1) * gap) / CGFloat(columns),
                                  (size.height - CGFloat(rows - 1) * gap) / CGFloat(rows)))
            let gridWidth = CGFloat(columns) * cell + CGFloat(columns - 1) * gap
            let gridHeight = CGFloat(rows) * cell + CGFloat(rows - 1) * gap
            let origin = CGPoint(x: (size.width - gridWidth) / 2, y: (size.height - gridHeight) / 2)

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

            let rendered = rendered ?? PixelFontRenderer.render(text: text, baseStyle: font, styleRuns: styleRuns, width: columns, height: rows, xOffset: xOffset, yOffset: yOffset)
            for y in 0..<rows {
                for x in 0..<columns {
                    let rect = CGRect(
                        x: origin.x + CGFloat(x) * (cell + gap),
                        y: origin.y + CGFloat(y) * (cell + gap),
                        width: cell,
                        height: cell
                    )
                    let fill: Color = rendered.pixels[y][x]
                        ? pixelColor(x: x, y: y, characterIndex: rendered.characterIndexes[y][x])
                        : Color(red: 0.04, green: 0.06, blue: 0.05)
                    context.fill(Path(roundedRect: rect, cornerRadius: max(0.5, cell * 0.12)), with: .color(fill))
                }
            }
        }
        .aspectRatio(80.0 / 7.0, contentMode: .fit)
        .background(Color.black)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(showsBorder ? Color(nsColor: .systemGray) : Color.clear, lineWidth: showsBorder ? 2 : 0)
                .allowsHitTesting(false)
        )
    }

    private func pixelColor(x: Int, y: Int, characterIndex: Int?) -> Color {
        guard let characterIndex,
              let run = styleRuns.last(where: {
                  characterIndex >= $0.location &&
                  characterIndex < $0.location + $0.length &&
                  !["{font5}", "{font7}"].contains($0.token.lowercased())
              }) else {
            return palette.color(x: x, y: y, characterIndex: characterIndex, fallback: color)
        }
        switch run.token.lowercased() {
        case "{red}":
            return .red
        case "{green}":
            return .green
        case "{orange}", "{yellow}":
            return .orange
        case "{bands}":
            return AppPalette.horizontalBands.color(x: x, y: y, characterIndex: characterIndex, fallback: color)
        case "{characters}":
            return AppPalette.characterStripes.color(x: x, y: y, characterIndex: characterIndex, fallback: color)
        case "{diagonal_down}":
            return AppPalette.diagonalDown.color(x: x, y: y, characterIndex: characterIndex, fallback: color)
        case "{diagonal_up}":
            return AppPalette.diagonalUp.color(x: x, y: y, characterIndex: characterIndex, fallback: color)
        default:
            return palette.color(x: x, y: y, characterIndex: characterIndex, fallback: color)
        }
    }
}

struct LEDPixelPageCanvas: View {
    let text: String
    let styleRuns: [CanvasStyleRun]
    let font: AppFont
    let color: Color
    let palette: AppPalette

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 3
            let rowHeight = max(18, (proxy.size.height - spacing * 6) / 7)
            VStack(spacing: spacing) {
                ForEach(Array(pageLines().enumerated()), id: \.offset) { _, line in
                    let columns = max(80, PixelFontRenderer.textWidth(line.text, baseStyle: font, styleRuns: line.styleRuns) + 2)
                    let rowWidth = max(proxy.size.width - 12, rowHeight * CGFloat(columns) / 7.0)
                    LEDPixelCanvas(
                        text: line.text,
                        styleRuns: line.styleRuns,
                        font: font,
                        color: color,
                        palette: palette,
                        xOffset: 0,
                        showsBorder: false,
                        columns: columns
                    )
                    .frame(width: rowWidth, alignment: .leading)
                    .frame(height: rowHeight)
                    .clipped()
                }
            }
            .padding(6)
        }
        .background(Color.black)
    }

    private func pageLines() -> [(text: String, styleRuns: [CanvasStyleRun])] {
        let displayText = RescueModel.displayTextForCanvas(text)
        let nsText = displayText as NSString
        let ranges = nsText.lineRanges
        var lines: [(text: String, styleRuns: [CanvasStyleRun])] = ranges.prefix(7).map { lineRange in
            var contentRange = lineRange
            while contentRange.length > 0 {
                let last = nsText.character(at: contentRange.location + contentRange.length - 1)
                if last == 10 || last == 13 {
                    contentRange.length -= 1
                } else {
                    break
                }
            }
            let lineText = nsText.substring(with: contentRange)
            let runs = styleRuns.compactMap { run -> CanvasStyleRun? in
                let intersectionStart = max(run.location, contentRange.location)
                let intersectionEnd = min(run.location + run.length, contentRange.location + contentRange.length)
                guard intersectionEnd > intersectionStart else { return nil }
                return CanvasStyleRun(
                    location: intersectionStart - contentRange.location,
                    length: intersectionEnd - intersectionStart,
                    token: run.token
                )
            }
            return (lineText, runs)
        }
        while lines.count < 7 {
            lines.append(("", []))
        }
        return lines
    }
}

struct LEDPreview: View {
    let text: String
    let effect: SigmaEffect
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .padding(.horizontal, 18)
            }
            .aspectRatio(80.0 / 7.0, contentMode: .fit)
            Text(effect.name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct PlaylistsView: View {
    @ObservedObject var model: RescueModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Playlist Draft")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    model.addPlaylistItem()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Button {
                    model.removeSelectedPlaylistItem()
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(model.selectedPlaylistItem == nil)
            }

            Table(model.playlistItems, selection: $model.selectedPlaylistItem) {
                TableColumn("Message") { item in
                    Text(item.text)
                }
                TableColumn("In") { item in
                    Text(item.inMode.name)
                }
                TableColumn("Out") { item in
                    Text(item.outMode.name)
                }
                TableColumn("Hold") { item in
                    Text("\(item.pauseSeconds)s")
                }
            }

            Text("Playlist sending will reuse the same SEQUENT.SYS mechanism we decoded; this view is the native replacement for Sigma Play's list manager.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Playlists")
    }
}

struct SystemSetView: View {
    @ObservedObject var model: RescueModel

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $model.systemName)
                    .textFieldStyle(.roundedBorder)
                    .userEntryField()
                LabeledContent("Width", value: "80")
                LabeledContent("Height", value: "7")
                LabeledContent("Firmware", value: "A512-05")
                LabeledContent("Hardware", value: "5205")
            }
            Section("Network") {
                TextField("IP address", text: $model.systemIP)
                    .textFieldStyle(.roundedBorder)
                    .userEntryField()
                TextField("Gateway", text: $model.systemGateway)
                    .textFieldStyle(.roundedBorder)
                    .userEntryField()
                TextField("Subnet mask", text: $model.systemMask)
                    .textFieldStyle(.roundedBorder)
                    .userEntryField()
                LabeledContent("MAC", value: "00-1D-6F-00-D4-50")
            }
            Section("Addressing") {
                Stepper("Group Addr \(model.systemGroupAddress)", value: $model.systemGroupAddress, in: 1...255)
                Stepper("Unit Addr \(model.systemUnitAddress)", value: $model.systemUnitAddress, in: 1...255)
                Picker("Baud Rate 1", selection: $model.systemBaud1) {
                    ForEach([9600, 19200], id: \.self) { baud in
                        Text("\(baud)").tag(baud)
                    }
                }
                .disabled(true)
                Picker("Baud Rate 2", selection: $model.systemBaud2) {
                    ForEach([9600, 19200], id: \.self) { baud in
                        Text("\(baud)").tag(baud)
                    }
                }
                .disabled(true)
                Text("Baud fields are shown from the Sigma Play screen but are locked until we capture one-change baud writes.")
                    .foregroundStyle(.secondary)
            }
            Section("Brightness / Power") {
                Toggle("Half Brightness", isOn: $model.systemHalfBrightnessEnabled)
                HStack {
                    TextField("Half from HH:MM", text: $model.systemHalfBrightnessStart)
                        .textFieldStyle(.roundedBorder)
                        .userEntryField()
                    TextField("To HH:MM", text: $model.systemHalfBrightnessEnd)
                        .textFieldStyle(.roundedBorder)
                        .userEntryField()
                }
                Toggle("Power Schedule", isOn: $model.systemPowerEnabled)
                HStack {
                    TextField("On HH:MM", text: $model.systemPowerOn)
                        .textFieldStyle(.roundedBorder)
                        .userEntryField()
                    TextField("Off HH:MM", text: $model.systemPowerOff)
                        .textFieldStyle(.roundedBorder)
                        .userEntryField()
                }
            }
            Section("Startup") {
                TextField("Serial Number", text: $model.systemSerialNumber)
                    .textFieldStyle(.roundedBorder)
                    .userEntryField()
                TextField("LED Bin", text: $model.systemLedBin)
                    .textFieldStyle(.roundedBorder)
                    .userEntryField()
                    .disabled(true)
                Toggle("Show Start-Up Information", isOn: $model.systemShowStartupInfo)
                    .disabled(true)
                Text("LED Bin and start-up display are visible for reference only; their write offsets are not confirmed yet.")
                    .foregroundStyle(.secondary)
            }
            Section("SysInfoFile") {
                LabeledContent("Source", value: model.systemConfigSourcePath)
                LabeledContent("Prepared file", value: model.preparedConfigPath.isEmpty ? "Not prepared yet" : model.preparedConfigPath)
                Text(model.systemStatus)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        model.prepareSystemConfig()
                    } label: {
                        Label("Prepare SysInfoFile", systemImage: "doc.badge.gearshape")
                    }

                    Button {
                        model.chooseConfigSource()
                    } label: {
                        Label("Choose SysInfoFile", systemImage: "folder")
                    }

                    Button {
                        model.uploadPreparedSystemConfig()
                    } label: {
                        Label("Write SysInfoFile", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.preparedConfigPath.isEmpty || model.isSending)
                }
            }
            Section("Decode Coverage") {
                Text("Mapped from captures: name, IP, gateway, subnet mask, group/unit address, power schedule, half brightness, serial number. Baud, LED Bin, start-up info, daylight saving, display mode, and other Sigma Play options still need one-change captures before native writes should alter those bytes.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("System Set")
    }
}

struct LogView: View {
    @ObservedObject var model: RescueModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Session log")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    model.logLines.removeAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }

            ScrollView {
                Text(model.logLines.joined(separator: "\n"))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .navigationTitle("Log")
    }
}

