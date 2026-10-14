import Foundation
import Testing
@testable import SpaceMouseBroker

struct ArbiterTests {
    private func claimant(_ id: Int, pid: Int32 = 0, apps: [String] = [], background: Bool = false,
                          lastFrontUse: Int? = nil) -> Claimant {
        Claimant(id: id, processID: pid == 0 ? Int32(100 + id) : pid, claim: Claim(apps: apps, background: background),
                 connected: id, lastFrontUse: lastFrontUse)
    }

    @Test func frontClaimBeatsBackground() {
        let stagehand = claimant(1, background: true)
        let kugelblitz = claimant(2, apps: ["me.metaebene.Kugelblitz"])
        let decision = Arbiter.decide([stagehand, kugelblitz], frontmostApp: "me.metaebene.Kugelblitz", frontmostProcess: 102)
        #expect(decision == .init(holder: 2, throughFront: true))
    }

    @Test func backgroundWhenNoClaimNamesTheFrontApp() {
        let stagehand = claimant(1, background: true)
        let shuttle = claimant(2, apps: ["com.cockos.reaper"])
        #expect(Arbiter.decide([stagehand, shuttle], frontmostApp: "com.apple.Safari", frontmostProcess: 7)
            == .init(holder: 1, throughFront: false))
    }

    @Test func nobodyWithoutMatchingClaim() {
        let shuttle = claimant(1, apps: ["com.cockos.reaper"])
        #expect(Arbiter.decide([shuttle], frontmostApp: "com.apple.Safari", frontmostProcess: 7).holder == nil)
        #expect(Arbiter.decide([], frontmostApp: nil, frontmostProcess: nil).holder == nil)
    }

    /// Space Glider steers Kugelblitz only if Kugelblitz has no client of its own.
    @Test func theFrontProcessItselfBeatsOneSteeringIt() {
        let glider = claimant(1, apps: ["me.metaebene.Kugelblitz", "com.apple.Maps"])
        let kugelblitz = claimant(2, pid: 500, apps: ["me.metaebene.Kugelblitz"])
        #expect(Arbiter.decide([glider, kugelblitz], frontmostApp: "me.metaebene.Kugelblitz", frontmostProcess: 500).holder == 2)
        #expect(Arbiter.decide([glider, kugelblitz], frontmostApp: "com.apple.Maps", frontmostProcess: 600).holder == 1)
    }

    /// In the background, whoever last had it in front wins; a client that never had it in front comes last.
    @Test func backgroundGoesToTheLatestFrontUse() {
        let stagehand = claimant(1, background: true)
        let kugelblitz = claimant(2, apps: ["me.metaebene.Kugelblitz"], background: true, lastFrontUse: 3)
        let other = claimant(3, apps: ["x"], background: true, lastFrontUse: 7)
        #expect(Arbiter.decide([stagehand, kugelblitz], frontmostApp: "com.apple.finder", frontmostProcess: 1).holder == 2)
        #expect(Arbiter.decide([stagehand, kugelblitz, other], frontmostApp: "com.apple.finder", frontmostProcess: 1).holder == 3)
        // Two that never had it in front: the earlier connection.
        let late = claimant(4, background: true)
        #expect(Arbiter.decide([late, stagehand], frontmostApp: nil, frontmostProcess: nil).holder == 1)
    }
}

struct WireTests {
    @Test func messagesSurviveLines() {
        var decoder = LineDecoder<ClientMessage>()
        let hello = ClientMessage.hello(protocolVersion: 1, processID: 42, name: "Kugelblitz",
                                        claim: Claim(apps: ["me.metaebene.Kugelblitz"], background: true))
        let data = LineEncoder.encode(hello) + LineEncoder.encode(ClientMessage.takeOver(version: 2))
        // Split in the middle of the first line: nothing until the newline arrives.
        #expect(decoder.feed(data.prefix(10)).isEmpty)
        #expect(decoder.feed(data.dropFirst(10)) == [hello, .takeOver(version: 2)])
    }

    @Test func newestBrokerIsNotReplacedByAnOlderOne() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let place = BrokerPlace(directory: directory)
        place.recordNewest(.init(version: 2, path: "/bin/sh"))
        place.recordNewest(.init(version: 1, path: "/bin/ls"))
        #expect(place.readNewest() == .init(version: 2, path: "/bin/sh"))
        // A newer one recorded whose program is gone does not count.
        place.recordNewest(.init(version: 5, path: "/nonexistent"))
        place.recordNewest(.init(version: 3, path: "/bin/ls"))
        #expect(place.readNewest() == .init(version: 3, path: "/bin/ls"))
    }
}
