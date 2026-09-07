import XCTest
@testable import Clipwise

final class ClipboardItemTests: XCTestCase {

    func testGenerateHashIsDeterministic() {
        let representations = [(type: "public.utf8-plain-text", data: Data("hello".utf8))]
        XCTAssertEqual(
            ClipboardItem.generateHash(from: representations),
            ClipboardItem.generateHash(from: representations)
        )
    }

    func testGenerateHashChangesWhenContentChanges() {
        let before = [(type: "public.utf8-plain-text", data: Data("hello".utf8))]
        let after = [(type: "public.utf8-plain-text", data: Data("hello!".utf8))]
        XCTAssertNotEqual(
            ClipboardItem.generateHash(from: before),
            ClipboardItem.generateHash(from: after)
        )
    }

    func testGenerateHashIsSHA256Hex() {
        let hash = ClipboardItem.generateHash(from: [(type: "t", data: Data("x".utf8))])
        XCTAssertEqual(hash.count, 64)
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit })
    }

    func testGenerateTitleUsesFirstNonEmptyLine() {
        XCTAssertEqual(ClipboardItem.generateTitle(forText: "\n\n  first\nsecond"), "first")
    }

    func testGenerateTitleCapsAtMaxTitleLength() {
        let long = String(repeating: "a", count: 500)
        XCTAssertEqual(
            ClipboardItem.generateTitle(forText: long).count,
            Constants.maxTitleLength
        )
    }

    func testGenerateTitleFallsBackForEmptyText() {
        XCTAssertEqual(ClipboardItem.generateTitle(forText: "   \n  "), "Unknown")
    }
}
