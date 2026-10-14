import SpaceJugglerProtocol

/// A connected client with its claim, as the broker keeps it.
public struct Claimant: Sendable, Equatable {
    public var id: Int
    public var processID: Int32
    public var claim: Claim
    /// Order of connecting; earlier is smaller.
    public var connected: Int
    /// When it last held the SpaceMouse because one of its apps was frontmost (arbitration count); nil if never.
    public var lastFrontUse: Int?

    public init(id: Int, processID: Int32, claim: Claim, connected: Int, lastFrontUse: Int? = nil) {
        self.id = id
        self.processID = processID
        self.claim = claim
        self.connected = connected
        self.lastFrontUse = lastFrontUse
    }
}

/// Decides who gets the SpaceMouse. Exactly one client at a time, nobody listens in (ADR-0001, Tim 2026-10-14).
public enum Arbiter {
    public struct Decision: Equatable, Sendable {
        public var holder: Int?
        /// Whether the holder got it through a frontmost app (and so counts as its latest front use).
        public var throughFront: Bool
    }

    /// 1. A claim naming the frontmost app beats every background claim. Among those, the frontmost process's own
    ///    client beats one that steers the app from outside, then the earlier connection.
    /// 2. Otherwise a background claim: one marked `backgroundLast` after all others; then whoever last had the
    ///    SpaceMouse in front, then the earlier connection.
    public static func decide(_ claimants: [Claimant], frontmostApp: String?, frontmostProcess: Int32?) -> Decision {
        if let frontmostApp {
            let front = claimants.filter { $0.claim.apps.contains(frontmostApp) }
            if let winner = front.min(by: { a, b in
                let aOwn = a.processID == frontmostProcess, bOwn = b.processID == frontmostProcess
                return aOwn != bOwn ? aOwn : a.connected < b.connected
            }) {
                return Decision(holder: winner.id, throughFront: true)
            }
        }
        let background = claimants.filter(\.claim.background)
        let winner = background.min { a, b in
            let aLast = a.claim.backgroundLast ?? false, bLast = b.claim.backgroundLast ?? false
            if aLast != bLast { return bLast }
            return switch (a.lastFrontUse, b.lastFrontUse) {
            case let (x?, y?) where x != y: x > y
            case (_?, nil): true
            case (nil, _?): false
            default: a.connected < b.connected
            }
        }
        return Decision(holder: winner?.id, throughFront: false)
    }
}
