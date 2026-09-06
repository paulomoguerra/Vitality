import XCTest

/// Moving an item to the Trash is only successful once FileManager has
/// returned a destination and that destination can be seen on disk. These
/// tests exercise the verification boundary without touching the user's real
/// Trash: the filesystem check is injected as a closure.
final class TrashReliabilityTests: XCTestCase {

    func testAcceptsAResultingURLThatExists() {
        let source = URL(fileURLWithPath: "/tmp/report.pdf")
        let destination = URL(fileURLWithPath: "/tmp/.Trash/report.pdf")

        let result = TrashMover.verifyDestination(
            source: source,
            resultingURL: destination,
            fileExists: { $0 == destination }
        )

        guard case .success(let receipt) = result else {
            return XCTFail("A returned destination that exists should be accepted")
        }
        XCTAssertEqual(receipt.sourceURL, source)
        XCTAssertEqual(receipt.destinationURL, destination)
    }

    func testRejectsMissingResultingURL() {
        let result = TrashMover.verifyDestination(
            source: URL(fileURLWithPath: "/tmp/report.pdf"),
            resultingURL: nil,
            fileExists: { _ in true }
        )

        guard case .failure(let error) = result else {
            return XCTFail("A missing destination must not be reported as success")
        }
        XCTAssertTrue(error.message.localizedCaseInsensitiveContains("confirm"))
    }

    /// `trashItem` deletes immediately on a volume with no Trash and leaves
    /// `resultingItemURL` nil. That is not "try again" — the file is gone.
    func testMissingDestinationAndGoneSourceIsAPermanentDelete() {
        let source = URL(fileURLWithPath: "/Volumes/USB/report.pdf")
        let result = TrashMover.verifyDestination(
            source: source,
            resultingURL: nil,
            fileExists: { _ in false }
        )

        guard case .failure(let error) = result else {
            return XCTFail("a permanent delete must not be reported as success")
        }
        XCTAssertTrue(error.message.localizedCaseInsensitiveContains("permanently"),
                      error.message)
        XCTAssertFalse(error.message.localizedCaseInsensitiveContains("try again"),
                       "retry language is a lie once the file is gone: \(error.message)")
    }

    func testRejectsAResultingURLThatDoesNotExist() {
        let destination = URL(fileURLWithPath: "/tmp/.Trash/report.pdf")

        let result = TrashMover.verifyDestination(
            source: URL(fileURLWithPath: "/tmp/report.pdf"),
            resultingURL: destination,
            fileExists: { _ in false }
        )

        guard case .failure(let error) = result else {
            return XCTFail("A destination that cannot be verified must not be success")
        }
        XCTAssertTrue(error.message.localizedCaseInsensitiveContains("exist"))
    }

    /// The UI prints `localizedDescription`, so the struct is only useful
    /// if that string is the message we wrote, not a generic Cocoa one.
    func testActionErrorSurfacesTheMessageAsTheLocalizedDescription() {
        let error = ActionError("Couldn't move report.pdf to the Trash.")

        XCTAssertEqual(error.localizedDescription, error.message)
        XCTAssertEqual(error.errorDescription, error.message)
    }
}
