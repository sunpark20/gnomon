import ReportKit
import XCTest

final class ReportLinksTests: XCTestCase {
    func testGnomonTargetUsesTheExpectedGitHubForm() throws {
        let target = ReportTarget(
            appID: "gnomon",
            displayName: "Gnomon",
            template: "gnomon-bug.yml"
        )
        let metadata = ReportMetadata(
            version: "1.7.2",
            build: "1",
            os: "macOS 15.0",
            device: "Mac"
        )

        let link = try XCTUnwrap(target.github(metadata: metadata))
        let components = try XCTUnwrap(URLComponents(url: link.url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(values["template"], "gnomon-bug.yml")
        XCTAssertNil(values["labels"])
        XCTAssertNil(values["body"])
    }
}
