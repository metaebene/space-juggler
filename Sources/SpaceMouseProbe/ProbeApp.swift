import SwiftUI

/// SpaceMouse Probe (ADR-0006): asks at the device until a model is known, and writes a report.
@main
struct ProbeApp: App {
    @State private var probe = Probe()

    var body: some Scene {
        Window("SpaceMouse Probe", id: "probe") {
            ContentView()
                .environment(probe)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 1000, height: 760)
    }
}
