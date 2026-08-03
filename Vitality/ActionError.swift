import Foundation

/// A plain, user-facing failure message for actions Vitality performs itself
/// (quitting a process, trashing a file) as opposed to failures coming back
/// from Mole, which carry their own `MoleError`.
struct ActionError: LocalizedError, Equatable {
    let message: String

    init(_ message: String) { self.message = message }

    var errorDescription: String? { message }
}
