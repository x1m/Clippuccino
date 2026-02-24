import XCTest
@testable import Clippuccino

final class HistoryManagerTests: XCTestCase {
    func testMaxItemsTruncationKeepsNewest() {
        let manager = HistoryManager(maxItems: 2, ttlSeconds: 0)

        manager.add(text: "first")
        manager.add(text: "second")
        manager.add(text: "third")

        XCTAssertEqual(manager.items.map(\.text), ["third", "second"])
    }

    func testTTLExpiryRemovesExpiredItems() {
        let manager = HistoryManager(maxItems: 10, ttlSeconds: 5)
        let now = Date()

        manager.add(text: "expired", now: now.addingTimeInterval(-10))
        manager.add(text: "fresh", now: now.addingTimeInterval(-2))

        manager.removeExpiredItems(now: now)

        XCTAssertEqual(manager.items.map(\.text), ["fresh"])
    }

    func testDedupeSkipsConsecutiveDuplicate() {
        let manager = HistoryManager(maxItems: 10, ttlSeconds: 0)

        XCTAssertTrue(manager.add(text: "same"))
        XCTAssertFalse(manager.add(text: "same"))
        XCTAssertEqual(manager.items.count, 1)
    }

    func testEraseAllClearsHistory() {
        let manager = HistoryManager(maxItems: 10, ttlSeconds: 0)

        manager.add(text: "one")
        manager.add(text: "two")
        manager.eraseAll()

        XCTAssertTrue(manager.items.isEmpty)
    }
}
