import Foundation

/// A plain, user-facing failure message for actions Vitality performs on the
/// user's behalf — quitting a process, measuring a folder, trashing a file.
struct ActionError: LocalizedError, Equatable {
    let message: String

    init(_ message: String) { self.message = message }

    var errorDescription: String? { message }
}
