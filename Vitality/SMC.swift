import Foundation
import IOKit

/// Reads Apple's System Management Controller.
///
/// This is the one place Vitality steps outside documented API, and it is a
/// deliberate exception rather than a drift in standards. Neither die
/// temperature nor total system wattage has *any* public interface on macOS:
/// `powermetrics` needs root, IOReport is a private framework, and IOKit's HID
/// temperature services expose the sensors under opaque names (`PMU tdie7`)
/// that cannot be attributed to the CPU or the GPU. The SMC is the only source
/// that names what it is measuring.
///
/// What keeps that honest:
///
/// - It talks to `AppleSMC` through **public IOKit calls**. No private
///   framework is linked and no symbol is looked up at runtime, so nothing here
///   can break by an unavailable symbol — only by Apple retiring the driver's
///   protocol, which fails as "no reading" rather than a crash.
/// - Every entry point returns an optional. A Mac that answers nothing simply
///   shows no temperatures; it never shows a made-up one.
/// - It needs no root, no entitlement, and no helper tool.
///
/// It does require the app to stay outside the sandbox — a sandboxed process
/// cannot open the `AppleSMC` service at all.
final class SMC {

    /// One sensor discovered on this Mac, with its type resolved once.
    struct Sensor {
        let key: UInt32
        let name: String
        fileprivate let info: SMCKeyInfoData
    }

    private var connection: io_connect_t = 0

    /// `nil` on any Mac that won't open the service — the caller degrades to
    /// showing no thermal data rather than failing.
    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            return nil
        }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: - Reading

    /// Reads a key by its four-character name, e.g. `PSTR`.
    ///
    /// Resolves the key's type on every call, so it suits the handful of named
    /// keys read once per poll. Sensors found by `discoverSensors()` carry their
    /// type with them and go through `read(_:)` instead.
    func value(forKey name: String) -> Double? {
        let key = Self.fourCharCode(name)
        guard let info = keyInfo(for: key) else { return nil }
        return read(Sensor(key: key, name: name, info: info))
    }

    func read(_ sensor: Sensor) -> Double? {
        var input = SMCParamStruct()
        input.key = sensor.key
        input.keyInfo = sensor.info
        input.data8 = Self.cmdReadBytes
        guard let output = call(input) else { return nil }
        return Self.decode(output.bytes, type: sensor.info.dataType)
    }

    // MARK: - Discovery

    /// Walks the whole key table once and keeps the ones the caller wants.
    ///
    /// The suffixes differ between chips — an M4 has `Tp00…Tp3X` where an M1
    /// has neither — so the list has to be discovered rather than hardcoded.
    /// Around 2,200 keys means this costs real milliseconds; it belongs on a
    /// background queue, called once, and cached.
    func discoverSensors(matching prefixes: [String]) -> [Sensor] {
        guard let count = keyCount() else { return [] }
        var found: [Sensor] = []

        for index in 0..<count {
            var input = SMCParamStruct()
            input.data8 = Self.cmdReadIndex
            input.data32 = UInt32(index)
            guard let output = call(input) else { continue }

            let name = Self.string(from: output.key)
            guard prefixes.contains(where: name.hasPrefix),
                  let info = keyInfo(for: output.key) else { continue }
            found.append(Sensor(key: output.key, name: name, info: info))
        }
        return found
    }

    private func keyCount() -> Int? {
        guard let value = value(forKey: "#KEY") else { return nil }
        return Int(value)
    }

    private func keyInfo(for key: UInt32) -> SMCKeyInfoData? {
        var input = SMCParamStruct()
        input.key = key
        input.data8 = Self.cmdReadKeyInfo
        guard let output = call(input), output.keyInfo.dataSize > 0 else { return nil }
        return output.keyInfo
    }

    // MARK: - Transport

    private func call(_ input: SMCParamStruct) -> SMCParamStruct? {
        guard connection != 0 else { return nil }
        var input = input
        var output = SMCParamStruct()
        var size = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(connection, Self.selectorHandleYPCEvent,
                                               &input, MemoryLayout<SMCParamStruct>.stride,
                                               &output, &size)
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    // MARK: - Encoding

    private static let selectorHandleYPCEvent: UInt32 = 2
    private static let cmdReadBytes: UInt8 = 5
    private static let cmdReadIndex: UInt8 = 8
    private static let cmdReadKeyInfo: UInt8 = 9

    static func fourCharCode(_ name: String) -> UInt32 {
        name.utf8.reduce(UInt32(0)) { ($0 << 8) + UInt32($1) }
    }

    static func string(from code: UInt32) -> String {
        let bytes = [UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
                     UInt8((code >> 8) & 0xff), UInt8(code & 0xff)]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    /// The SMC returns big-endian values in one of a handful of tagged types.
    /// Anything unrecognised reads as `nil` rather than as a plausible number.
    private static func decode(_ raw: SMCBytes, type: UInt32) -> Double? {
        let b = withUnsafeBytes(of: raw) { Array($0) }

        switch string(from: type) {
        case "flt ":
            let bits = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
            return Double(Float(bitPattern: bits))
        case "ioft":
            // 8-byte fixed point, 48.16 — the SMC's usual float on Apple silicon.
            let whole = UInt64(b[0]) << 48 | UInt64(b[1]) << 40 | UInt64(b[2]) << 32
                | UInt64(b[3]) << 24 | UInt64(b[4]) << 16 | UInt64(b[5]) << 8 | UInt64(b[6])
            return Double(whole) / 65_536
        case "ui8 ":
            return Double(b[0])
        case "ui16":
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32":
            return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        case "si8 ":
            return Double(Int8(bitPattern: b[0]))
        case "si16":
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1])))
        default:
            return nil
        }
    }
}

// MARK: - Driver structures
//
// These mirror the layout `AppleSMC` expects, byte for byte. They are not
// Vitality's to design — the field order and padding are the driver's.

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    var dataSize: IOByteCount32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}
