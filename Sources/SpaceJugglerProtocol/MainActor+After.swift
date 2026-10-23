import Foundation

extension MainActor {
    /// Runs `body` on the main actor after `delay` seconds, through the main queue (nothing to cancel; a
    /// `DispatchWorkItem` where that matters).
    package static func after(_ delay: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(body) }
    }
}
