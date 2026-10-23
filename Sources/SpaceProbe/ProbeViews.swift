import AppKit
import SpaceJugglerClient
import SpaceMouseKitUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(Probe.self) private var probe

    var body: some View {
        @Bindable var probe = probe
        NavigationSplitView {
            List(probe.sessions, selection: $probe.selection) { session in
                DeviceRow(session: session).tag(session.id)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .overlay {
                if probe.sessions.isEmpty {
                    ContentUnavailableView {
                        Label("No SpaceMouse", systemImage: "cube.transparent")
                    } description: {
                        if let problem = probe.problem { Text(verbatim: problem) } else {
                            Text("Connect a SpaceMouse by cable, receiver or Bluetooth.")
                        }
                    }
                }
            }
        } detail: {
            if let session = probe.selected {
                TestView(session: session).id(ObjectIdentifier(session))
            } else {
                Text("Space Probe guides you through every key and every movement of your SpaceMouse and writes down what it sends, so that Space Juggler can support it.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360).padding()
            }
        }
    }
}

struct DeviceRow: View {
    let session: ProbeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: session.device.name).font(.headline)
            Text(verbatim: session.idsAndTransport).font(.caption).foregroundStyle(.secondary)
            Group {
                switch session.step {
                case .start: Text("Not tested yet")
                case .report: Text("Report created")
                default: Text("Step \(ProbeSession.Step.shown.firstIndex(of: session.step).map { $0 + 1 } ?? 0) of \(ProbeSession.Step.shown.count)")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

extension ProbeSession.Step {
    var title: LocalizedStringKey {
        switch self {
        case .start: "Start"
        case .description: "Device"
        case .keys: "Keys"
        case .cap: "Cap"
        case .led: "LED"
        case .label: "Label"
        case .summary: "Check"
        case .report: "Report"
        }
    }
}

// MARK: - The test

struct TestView: View {
    @Environment(Probe.self) private var probe
    @Bindable var session: ProbeSession

    var body: some View {
        VStack(spacing: 0) {
            if session.step != .start {
                StepBar(session: session).padding(.horizontal, 24).padding(.vertical, 12)
                Divider()
            }
            ScrollView {
                page
                    .padding(28)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            if session.step != .start && session.step != .report {
                Divider()
                footer.padding(.horizontal, 24).padding(.vertical, 12)
            }
        }
        .navigationTitle(Text(verbatim: session.device.name))
    }

    @ViewBuilder private var page: some View {
        switch session.step {
        case .start: StartPage(session: session)
        case .description: DescriptionPage(session: session)
        case .keys: KeysPage(session: session)
        case .cap: CapPage(session: session)
        case .led: LEDPage(session: session)
        case .label: LabelPage(session: session)
        case .summary: SummaryPage(session: session)
        case .report: ReportPage(session: session)
        }
    }

    private var footer: some View {
        HStack {
            if let previous = session.previous, previous != .start {
                Button("Back") { session.step = previous }
            }
            Spacer()
            if session.step == .keys || session.step == .cap { FrontNotice() }
            Spacer()
            if session.step == .summary {
                Button("Create Report") { probe.createReport(session) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else if let next = session.next {
                Button("Continue") { session.step = next }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!session.isDone(session.step))
            }
        }
    }
}

/// The steps, the current one stressed, those done ticked.
struct StepBar: View {
    let session: ProbeSession

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(ProbeSession.Step.shown.filter { $0 != .led || session.hasLED }.enumerated()), id: \.element) { index, step in
                if index > 0 { Rectangle().fill(.quaternary).frame(height: 1).frame(maxWidth: 28) }
                let current = step == session.step
                let done = step < session.step
                HStack(spacing: 4) {
                    Image(systemName: done ? "checkmark.circle.fill" : current ? "\(index + 1).circle.fill" : "\(index + 1).circle")
                        .foregroundStyle(done ? Color.green : current ? Color.accentColor : Color.secondary)
                    Text(step.title).fontWeight(current ? .semibold : .regular)
                        .foregroundStyle(current ? .primary : .secondary)
                }
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Only the app in front gets the SpaceMouse.
struct FrontNotice: View {
    @Environment(Probe.self) private var probe

    var body: some View {
        if probe.driverRunning {
            Label("3Dconnexion's driver holds the SpaceMouse", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange).font(.callout)
        } else if !probe.holds {
            Label("Keep this window in front", systemImage: "hand.raised").foregroundStyle(.orange).font(.callout)
        }
    }
}

struct PageTitle: View {
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.bold())
            Text(text).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Pages

struct StartPage: View {
    @Environment(Probe.self) private var probe
    let session: ProbeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: session.device.name).font(.largeTitle.bold())
                Text(verbatim: session.idsAndTransport).foregroundStyle(.secondary)
                knowledge.font(.title3)
            }
            Text("The test takes about three minutes. You will:").font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Label("let the probe read what the device declares about itself", systemImage: "doc.text.magnifyingglass")
                Label("press every key once and say what is printed on it", systemImage: "keyboard")
                Label("move the cap in each of twelve directions", systemImage: "move.3d")
                if session.hasLED { Label("say whether the LED lights up", systemImage: "lightbulb") }
                Label("type what is printed on the device and its label", systemImage: "tag")
                Label("check everything and create a report", systemImage: "checkmark.seal")
            }
            Text("The report stays on your Mac until you export it or post it on GitHub. Nothing on the device is changed, except for switching its LED.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if probe.driverRunning {
                Label("3Dconnexion's driver holds the SpaceMouse, so the probe gets no keys or movements. Quit 3Dconnexion's helper before starting; it starts again at your next login.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Button {
                if session.description == nil || session.description?.error != nil { probe.describe(session) }
                session.step = .description
            } label: {
                Text("Start Test").font(.title3).padding(.horizontal, 12).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private var knowledge: some View {
        switch session.device.knowledge {
        case .checked: Text("Space Juggler knows this model, checked at a device. A report still helps if anything differs.")
        case .published: Text("Space Juggler knows this model from public sources only. Your report makes it a checked one.")
        case .guessed: Text("Space Juggler does not know this model yet. Your report teaches it.")
        case nil: Text("The Space Juggler running is older than this probe.")
        }
    }
}

struct DescriptionPage: View {
    @Environment(Probe.self) private var probe
    let session: ProbeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(title: "Device", text: "First the probe reads what the device declares about itself. You need not do anything.")
            if let description = session.description {
                if let error = description.error {
                    Label { Text("Could not be read: \(error)") } icon: { Image(systemName: "xmark.octagon") }
                        .foregroundStyle(.red)
                } else if let parsed = session.descriptor {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow { Text("Keys").foregroundStyle(.secondary); Text(verbatim: "\(parsed.buttonUsages.count)") }
                        GridRow { Text("Axes").foregroundStyle(.secondary); Text(verbatim: "6, ±\(parsed.axisLogicalMaximum ?? 0)") }
                        GridRow { Text("LED").foregroundStyle(.secondary); Text(parsed.hasLED ? "yes" : "no") }
                        GridRow {
                            Text("Further data").foregroundStyle(.secondary)
                            Text("\(description.featureReports.filter { $0.bytes != nil }.count) of \(description.featureReports.count) readable")
                        }
                        if let serial = session.device.serialNumber {
                            GridRow { Text("Serial number").foregroundStyle(.secondary); Text(verbatim: serial).textSelection(.enabled) }
                        }
                    }
                    .font(.title3)
                    Label("Read.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text("The description could not be understood; it goes into the report as it is.")
                }
            } else {
                ProgressView("Reading…")
            }
            Button("Read Again") { probe.describe(session) }
        }
    }
}

struct KeysPage: View {
    @Bindable var session: ProbeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(title: "Keys", text: "Press each key of your SpaceMouse once. For every key, type what is printed on it; leave the field empty if nothing is.")
            HStack(alignment: .top, spacing: 28) {
                SpaceMouseTopView(axes: session.axes, fullScale: session.fullScale, sideButtons: session.sideButtons)
                    .frame(width: 180, height: 180)
                VStack(alignment: .leading, spacing: 10) {
                    if session.keys.isEmpty {
                        Text("Waiting for the first key…").foregroundStyle(.secondary)
                    }
                    ForEach(Array(session.keys.enumerated()), id: \.element) { index, bit in
                        HStack {
                            Image(systemName: session.heldBits.contains(bit) ? "circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(session.heldBits.contains(bit) ? Color.orange : Color.green)
                            Text("Key \(index + 1)").frame(width: 70, alignment: .leading)
                            TextField("Nothing printed", text: Binding(get: { session.labels[bit] ?? "" },
                                                                            set: { session.labels[bit] = $0 }))
                                .frame(width: 220)
                        }
                    }
                }
            }
            let declared = session.declaredBits.count
            if declared > 0 {
                Text("\(session.keys.count) of \(declared) keys found").font(.headline)
            }
            if declared == 0 || session.keys.count < declared {
                Toggle("My SpaceMouse has no further keys", isOn: $session.noMoreKeys)
            }
            if !session.keys.isEmpty {
                Button("Start Over") { session.forgetKeys() }
            }
        }
    }
}

struct CapPage: View {
    let session: ProbeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(title: "Cap", text: "Move the cap as asked, as far as it goes, then let go. The next direction follows by itself.")
            HStack(alignment: .center, spacing: 28) {
                SpaceMouseTopView(axes: session.axes, fullScale: session.fullScale, sideButtons: session.sideButtons,
                                  asked: session.asked, done: Set(session.results.keys))
                    .frame(width: 240, height: 240)
                VStack(alignment: .leading, spacing: 12) {
                    if let asked = session.asked {
                        Text(verbatim: asked.localizedInstruction).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                        Text("as far as it goes, then let go").font(.title3).foregroundStyle(.secondary)
                    } else {
                        Label("All twelve directions recorded.", systemImage: "checkmark.circle.fill")
                            .font(.title2).foregroundStyle(.green)
                    }
                    Text("\(session.results.count) of 12").font(.headline)
                }
            }
            if !session.unexpectedDirections.isEmpty {
                Text("Some directions moved another axis than on the models known so far. That is fine if you moved the cap as asked; it goes into the report.")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if !session.results.isEmpty { Button("Start Over") { session.redoCap() } }
        }
    }
}

struct LEDPage: View {
    @Environment(Probe.self) private var probe
    @Bindable var session: ProbeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "LED", text: "The probe switches the LED of your SpaceMouse on and off. Watch it.")
            question(button: "Switch LED On", asks: "Did the LED light up?", answer: $session.ledLit) {
                probe.setLED(true, session)
            }
            if session.ledLit != nil {
                question(button: "Switch LED Off", asks: "Did the LED go out?", answer: $session.ledWentOut) {
                    probe.setLED(false, session)
                }
            }
        }
    }

    private func question(button: LocalizedStringKey, asks: LocalizedStringKey, answer: Binding<Bool?>,
                          action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(button, action: action).controlSize(.large)
            HStack(spacing: 12) {
                Text(asks).font(.title3)
                Picker(asks, selection: answer) {
                    Text("Yes").tag(Bool?.some(true))
                    Text("No").tag(Bool?.some(false))
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140)
            }
        }
    }
}

struct LabelPage: View {
    @Bindable var session: ProbeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(title: "Label", text: "What is printed on your SpaceMouse? Look on top and on the label underneath.")
            Form {
                TextField("Model name, as printed", text: $session.printedName)
                TextField("Serial number (S/N)", text: $session.printedSerial).disabled(session.noSerialPrinted)
                Toggle("No serial number printed", isOn: $session.noSerialPrinted)
            }
            .formStyle(.grouped)
            .frame(maxWidth: 520)
            if let read = session.device.serialNumber {
                Text("The device itself reports: \(read)").foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
}

struct SummaryPage: View {
    @Bindable var session: ProbeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(title: "Check", text: "Is everything right? Change what is not, add what else you know, then create the report.")
            Form {
                Section {
                    row("Model") { Text(verbatim: session.device.name) }
                    row("IDs") { Text(verbatim: session.idsAndTransport) }
                } header: { header("Device", step: .description) }
                Section {
                    if session.keys.isEmpty { Text("none") }
                    ForEach(Array(session.keys.enumerated()), id: \.element) { index, bit in
                        row("Key \(index + 1)") {
                            if let label = session.labels[bit], !label.isEmpty { Text(verbatim: label) } else { Text("nothing printed") }
                        }
                    }
                } header: { header("Keys", step: .keys) }
                Section {
                    let odd = session.unexpectedDirections
                    if odd.isEmpty {
                        Text("All twelve directions as expected.")
                    } else {
                        ForEach(odd, id: \.self) { direction in
                            let result = session.results[direction]!
                            LabeledContent {
                                Text(verbatim: "\(result.sign > 0 ? "+" : "−")\(SpaceMouseAxes.axisNames[result.axis])")
                            } label: {
                                Text(verbatim: direction.localizedInstruction)
                            }
                        }
                    }
                } header: { header("Cap", step: .cap) }
                if session.hasLED {
                    Section {
                        row("Lit") { Text(answer(session.ledLit)) }
                        row("Went out") { Text(answer(session.ledWentOut)) }
                    } header: { header("LED", step: .led) }
                }
                Section {
                    row("Model name") { Text(verbatim: session.printedName) }
                    row("Serial number") {
                        if session.noSerialPrinted { Text("none printed") } else { Text(verbatim: session.printedSerial) }
                    }
                } header: { header("Label", step: .label) }
                Section("Anything else") {
                    TextField("Receiver or cable, firmware, what did not work …", text: $session.notes, axis: .vertical)
                        .lineLimit(3...8).labelsHidden()
                }
            }
            .formStyle(.grouped)
        }
    }

    private func row<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        LabeledContent { content() } label: { Text(title) }
    }

    private func header(_ title: LocalizedStringKey, step: ProbeSession.Step) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button("Change") { session.step = step }.buttonStyle(.link).font(.callout)
        }
    }

    private func answer(_ value: Bool?) -> LocalizedStringKey { value.map { $0 ? "yes" : "no" } ?? "not asked" }
}

struct ReportPage: View {
    @Environment(Probe.self) private var probe
    let session: ProbeSession
    @State private var showsJSON = false
    @State private var confirmsPosting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Report created", systemImage: "checkmark.seal.fill").font(.largeTitle.bold()).foregroundStyle(.green)
            Text("Thank you! The report is on your Mac. Post it on GitHub so that Space Juggler learns your SpaceMouse, or export it and send it another way.")
                .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let file = session.reportFile {
                HStack {
                    Text(verbatim: file.lastPathComponent).font(.callout.monospaced()).textSelection(.enabled)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }.buttonStyle(.link)
                }
            } else if let error = session.reportError {
                Label { Text("The report could not be saved on your Mac: \(error)") } icon: { Image(systemName: "exclamationmark.triangle") }
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button { confirmsPosting = true } label: { Label("Post on GitHub…", systemImage: "arrow.up.forward.app") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button { export() } label: { Label("Export…", systemImage: "square.and.arrow.up") }
                    .controlSize(.large)
            }
            Text("Posting copies the report and opens a new issue at github.com/metaebene/space-juggler in your browser; there you paste the report into the field “Report” and submit. You need a GitHub account. The issue is public and contains your device's serial number.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Show Report", isExpanded: $showsJSON) {
                Text(verbatim: String(decoding: session.report?.json ?? Data(), as: UTF8.self))
                    .font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            Divider()
            HStack {
                Button("Back to Check") { session.step = .summary }
                Button("Test Again") { probe.restart(session) }
            }
        }
        .alert("Post on GitHub", isPresented: $confirmsPosting) {
            Button("Copy Report and Open GitHub") { probe.sendToGitHub(session) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The report is copied to the clipboard. In the browser, paste it into the field “Report” (⌘V) and click “Create”. The issue is public.")
        }
    }

    private func export() {
        guard let report = session.report else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = session.reportFile?.lastPathComponent
            ?? String(format: "SpaceMouse %04X-%04X.json", session.device.vendorID, session.device.productID)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.json.write(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
