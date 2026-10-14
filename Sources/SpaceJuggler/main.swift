import AppKit

// Space Juggler.app (ADR-0002): an `LSUIElement` app, started by a client through Launch Services.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.run()
}
