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
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            .overlay {
                if probe.sessions.isEmpty {
                    ContentUnavailableView("No SpaceMouse", systemImage: "cube.transparent",
                                           description: Text(probe.problem ?? "Connect a SpaceMouse by cable, receiver or Bluetooth."))
                }
            }
        } detail: {
            if let session = probe.selected {
                SessionView(session: session).id(session.id)
            } else {
                Text("SpaceMouse Probe asks you to try every key and every direction of your SpaceMouse and writes down "
                     + "what it sends, so that Space Juggler can support it.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360).padding()
            }
        }
    }
}

struct DeviceRow: View {
    let session: ProbeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.device.name).font(.headline)
            Text(String(format: "%04X:%04X · %@", session.device.vendorID, session.device.productID, session.device.transport))
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(ProbeSession.Step.allCases) { step in
                    Image(systemName: session.isDone(step) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(session.isDone(step) ? .green : .secondary)
                        .help(step.title)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }
}

struct SessionView: View {
    @Environment(Probe.self) private var probe
    @Bindable var session: ProbeSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                notices
                live
                DescriptionStep(session: session)
                KeysStep(session: session)
                CapStep(session: session)
                if session.hasLED { LEDStep(session: session) }
                LabelStep(session: session)
                footer
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle(session.device.name)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.device.name).font(.title2.bold())
            Text(String(format: "%04X:%04X · %@ · %@", session.device.vendorID, session.device.productID,
                        session.device.transport, session.device.id))
                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Text(knowledgeText).font(.callout)
        }
    }

    private var knowledgeText: String {
        switch session.device.knowledge {
        case .checked: "Space Juggler knows this model, checked at a device. A report still helps if anything differs."
        case .published: "Space Juggler knows this model from public sources only. Your report makes it a checked one."
        case .guessed: "Space Juggler does not know this model yet; it guesses from what the device declares."
        case nil: "Space Juggler running is older than this probe."
        }
    }

    @ViewBuilder private var notices: some View {
        if probe.driverRunning {
            Notice(symbol: "exclamationmark.triangle",
                   text: "3Dconnexion's driver holds the SpaceMouse, so the probe gets no keys or axes. Quit 3Dconnexion's "
                       + "helper to record them (it starts again at the next login). The description works anyway.")
        } else if !probe.holds {
            Notice(symbol: "hand.raised",
                   text: "Keep this window in front: only then does the SpaceMouse report to the probe.")
        }
        if let problem = probe.problem { Notice(symbol: "info.circle", text: problem) }
    }

    private var live: some View {
        HStack(alignment: .top, spacing: 20) {
            let two = session.device.buttons.map { $0.contains(.left) } ?? (session.declaredBits == [0, 1])
            SpaceMouseTopView(axes: session.axes, fullScale: session.fullScale,
                              sideButtons: two ? (session.heldBits.contains(0), session.heldBits.contains(1)) : nil,
                              asked: session.asked, done: Set(session.results.keys))
                .frame(width: 200, height: 200)
            VStack(alignment: .leading, spacing: 8) {
                Text("Keys").font(.headline)
                KeyGrid(session: session)
                Text(session.axes.description).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text("\(session.reportsSeen) reports").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(session.isComplete ? "All done. Thank you!" : "Not everything is recorded yet; you can send what there is.")
                .font(.headline)
            Text("The report contains what the device declares and sends, what you typed, and its serial number. "
                 + "Sent to GitHub, it is public.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Save Report…") { save() }
                Button("Report on GitHub…") { probe.sendToGitHub(session) }
                    .buttonStyle(.borderedProminent)
                    .help("Opens a new issue at github.com/metaebene/space-juggler with the report (also on the clipboard).")
            }
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = String(format: "SpaceMouse %04X-%04X.json", session.device.vendorID, session.device.productID)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? probe.report(session).json.write(to: url)
    }
}

struct Notice: View {
    let symbol: String
    let text: String

    var body: some View {
        Label { Text(text) } icon: { Image(systemName: symbol) }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Every declared key, lit while held, with its label once known.
struct KeyGrid: View {
    let session: ProbeSession

    var body: some View {
        let bits = Array(Set(session.declaredBits).union(session.labels.keys).union(session.heldBits)).sorted()
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(bits, id: \.self) { bit in
                let held = session.heldBits.contains(bit)
                // Until labelled: what the catalog expects there, with a question mark.
                Text(session.labels[bit] ?? session.catalogName(bit).map { "\($0)?" } ?? "bit \(bit)")
                    .font(.caption.weight(session.labels[bit] == nil ? .regular : .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .frame(minWidth: 56)
                    .background(held ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.quaternary), in: Capsule())
                    .foregroundStyle(held ? .black : session.labels[bit] == nil ? .secondary : .primary)
            }
        }
        .frame(maxWidth: 480, alignment: .leading)
    }
}

/// One step of the checklist.
struct StepBox<Content: View>: View {
    let title: String
    let done: Bool
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
        } label: {
            Label(title, systemImage: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .primary)
                .font(.headline)
        }
    }
}

struct DescriptionStep: View {
    @Environment(Probe.self) private var probe
    let session: ProbeSession

    var body: some View {
        StepBox(title: "1. Description", done: session.isDone(.description)) {
            if let description = session.description {
                if let error = description.error {
                    Text("Not read: \(error)").foregroundStyle(.red)
                } else if let parsed = session.descriptor {
                    Text("Report descriptor: \(description.reportDescriptor.count) bytes, axes up to ±\(parsed.axisLogicalMaximum ?? 0), "
                         + "\(parsed.buttonUsages.count) keys, LED: \(parsed.hasLED ? "yes" : "no").")
                    let read = description.featureReports.filter { $0.bytes != nil }.count
                    Text("Feature reports: \(read) of \(description.featureReports.count) read"
                         + (description.featureReportsVia.map { " (through the \($0))" } ?? "") + ".")
                        .foregroundStyle(.secondary)
                } else {
                    Text("The report descriptor could not be parsed (\(description.reportDescriptor.count) bytes); it goes into the report as it is.")
                }
            } else {
                ProgressView().controlSize(.small)
            }
            Button("Read Again") { probe.describe(session) }
        }
    }
}

struct KeysStep: View {
    @Bindable var session: ProbeSession
    @State private var draft = ""

    var body: some View {
        StepBox(title: "2. Keys", done: session.isDone(.keys)) {
            Text("Press every key once, one after another, and type what is printed on it.")
            if let bit = session.unlabelled.first {
                HStack {
                    Text("Bit \(bit) – what is printed on that key?")
                    TextField("Label", text: $draft)
                        .frame(width: 160)
                        .onSubmit { save(bit) }
                    Button("OK") { save(bit) }.disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .onAppear { draft = session.catalogName(bit) ?? "" }
                .onChange(of: bit) { _, new in draft = session.catalogName(new) ?? "" }
            }
            let declared = session.declaredBits.count
            Text(declared > 0 ? "\(session.labels.count) of \(declared) keys the device declares." : "\(session.labels.count) keys.")
                .foregroundStyle(.secondary)
            if !session.labels.isEmpty {
                Button("Start Again") {
                    session.labels = [:]
                    session.unlabelled = []
                    session.noMoreKeys = false
                }
            }
            Toggle("There are no more keys", isOn: $session.noMoreKeys)
        }
    }

    private func save(_ bit: Int) {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        session.label(bit, draft)
    }
}

struct CapStep: View {
    let session: ProbeSession

    var body: some View {
        StepBox(title: "3. Cap", done: session.isDone(.axes)) {
            if let asked = session.asked {
                Text("\(asked.instruction) as far as it goes, then let go.").font(.title3)
            } else {
                Text("All twelve directions recorded.")
            }
            Text("\(session.results.count) of 12 directions.").foregroundStyle(.secondary)
            let odd = SpaceMouseAxes.Direction.allCases.filter { session.results[$0]?.asExpected == false }
            if !odd.isEmpty {
                Text("Not as on the models known so far: " + odd.map { direction in
                    let result = session.results[direction]!
                    return "\(direction.rawValue) → \(result.sign > 0 ? "+" : "−")\(SpaceMouseAxes.axisNames[result.axis])"
                }.joined(separator: ", ") + ". That is fine if it is what you did; it goes into the report.")
                .foregroundStyle(.orange)
            }
            if !session.results.isEmpty { Button("Start Again") { session.redoAxes() } }
        }
    }
}

struct LEDStep: View {
    @Environment(Probe.self) private var probe
    @Bindable var session: ProbeSession
    @State private var asking: Bool?

    var body: some View {
        StepBox(title: "4. LED", done: session.isDone(.led)) {
            HStack {
                Button("Switch LED On") { probe.setLED(true, session); asking = true }
                Button("Switch LED Off") { probe.setLED(false, session); asking = false }
            }
            if let asking {
                HStack {
                    Text(asking ? "Did the LED light up?" : "Did the LED go out?")
                    Button("Yes") { answer(asking, true) }
                    Button("No") { answer(asking, false) }
                }
            }
            Text("Lit: \(text(session.ledLit)) · went out: \(text(session.ledWentOut))").foregroundStyle(.secondary)
        }
    }

    private func answer(_ on: Bool, _ yes: Bool) {
        if on { session.ledLit = yes } else { session.ledWentOut = yes }
        asking = nil
    }

    private func text(_ value: Bool?) -> String { value.map { $0 ? "yes" : "no" } ?? "not asked" }
}

struct LabelStep: View {
    @Bindable var session: ProbeSession

    var body: some View {
        StepBox(title: "5. Label", done: session.isDone(.label)) {
            Text("What is printed on the device and on the label underneath it?")
            TextField("Model name, as printed", text: $session.printedName)
            HStack {
                TextField("Serial number (S/N)", text: $session.printedSerial).disabled(session.noSerialPrinted)
                Toggle("None printed", isOn: $session.noSerialPrinted)
            }
            if let read = session.device.serialNumber {
                Text("The device says: \(read)").foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("Anything else (receiver, firmware, what did not work):").padding(.top, 4)
            TextEditor(text: $session.notes).frame(height: 60).font(.body)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
        }
    }
}
