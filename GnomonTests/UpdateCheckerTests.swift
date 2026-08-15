//
//  UpdateCheckerTests.swift
//  GnomonTests
//
//  Version comparison rules for the GitHub-release updater.
//

import XCTest
@testable import Gnomon

final class UpdateCheckerTests: XCTestCase {
    func testNewerPatchVersion() {
        XCTAssertTrue(UpdateChecker.isVersion("1.8.1", newerThan: "1.8.0"))
    }

    func testSameVersionIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isVersion("1.8.0", newerThan: "1.8.0"))
    }

    func testOlderVersionIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isVersion("1.7.9", newerThan: "1.8.0"))
    }

    func testLeadingVPrefixIsIgnored() {
        XCTAssertTrue(UpdateChecker.isVersion("v2.0.0", newerThan: "1.8.0"))
        XCTAssertFalse(UpdateChecker.isVersion("v1.8.0", newerThan: "1.8.0"))
    }

    func testNumericNotLexicographicComparison() {
        XCTAssertTrue(UpdateChecker.isVersion("1.10", newerThan: "1.9"))
        XCTAssertFalse(UpdateChecker.isVersion("1.9", newerThan: "1.10"))
    }

    func testMissingSegmentsCountAsZero() {
        XCTAssertTrue(UpdateChecker.isVersion("1.8.0.1", newerThan: "1.8.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.8", newerThan: "1.8.0"))
    }

    func testGarbageInputDoesNotCrash() {
        XCTAssertFalse(UpdateChecker.isVersion("abc", newerThan: "1.8.0"))
        XCTAssertTrue(UpdateChecker.isVersion("2.0-beta", newerThan: "1.8.0"))
    }
}
