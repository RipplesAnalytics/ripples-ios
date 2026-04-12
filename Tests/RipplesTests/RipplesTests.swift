import XCTest
@testable import Ripples

final class RipplesTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Ripples.shared.reset()
    }

    func testIdentifyAndTrackEnqueue() {
        let config = RipplesConfig(projectToken: "00000000-0000-0000-0000-000000000000")
        config.flushIntervalSeconds = 0
        config.flushAt = 999
        Ripples.setup(config)

        Ripples.shared.identify("user_1", traits: ["email": "a@b.com"])
        Ripples.shared.track("did_thing", userId: "user_1", properties: ["area": "x"])

        XCTAssertEqual(Ripples.shared.queueDepth, 2)
    }

    func testEventSerialization() {
        let event = RipplesEvent(type: "track",
                                 properties: ["name": "x", "user_id": "u"])
        let data = RipplesEvent.toData(event)
        XCTAssertNotNil(data)

        let decoded = RipplesEvent.fromData(data!)
        XCTAssertEqual(decoded?["type"] as? String, "track")
        XCTAssertEqual(decoded?["name"] as? String, "x")
        XCTAssertNotNil(decoded?["sent_at"])
    }
}
