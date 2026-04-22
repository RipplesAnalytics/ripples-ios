import XCTest
@testable import Ripples

final class RipplesTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Ripples.shared.reset()
    }

    private func setupWithFreshToken() {
        let token = UUID().uuidString
        let config = RipplesConfig(projectToken: token)
        config.flushIntervalSeconds = 0
        config.flushAt = 999
        Ripples.setup(config)
    }

    func testIdentifyAndTrackEnqueue() {
        setupWithFreshToken()

        Ripples.shared.identify("user_1", traits: ["email": "a@b.com"])
        Ripples.shared.track("did_thing", properties: ["area": "x"])

        XCTAssertEqual(Ripples.shared.queueDepth, 2)
    }

    /// identify() persists user_id so later track/screen calls carry $user_id
    /// without the host app having to re-identify on every session.
    func testUserIdInjectedOnSubsequentEvents() {
        setupWithFreshToken()

        Ripples.shared.identify("user_42", traits: [:])
        Ripples.shared.track("did_thing")
        Ripples.shared.screen("Home")

        let props = Ripples.shared.lastEnqueuedProperties
        XCTAssertEqual(props?["$user_id"] as? String, "user_42")
    }

    func testEventSerialization() {
        let event = RipplesEvent(type: "track",
                                 properties: ["$name": "x", "$user_id": "u"])
        let data = RipplesEvent.toData(event)
        XCTAssertNotNil(data)

        let decoded = RipplesEvent.fromData(data!)
        XCTAssertEqual(decoded?["$type"] as? String, "track")
        XCTAssertEqual(decoded?["$name"] as? String, "x")
        XCTAssertNotNil(decoded?["$sent_at"])
    }
}
