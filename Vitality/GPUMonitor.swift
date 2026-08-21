import Foundation
import IOKit

/// Live GPU statistics read straight from the IOKit registry.
///
/// Apple exposes no public framework for GPU utilisation, and several tools
/// that claim to report it return -1 on Apple silicon. The real numbers live in
/// the IOAccelerator service's `PerformanceStatistics` dictionary.
///
/// An instance rather than a namespace so the device name can be resolved once.
/// Reading it walks up to the parent registry node and copies a CF property —
/// worth doing for a name that is fixed for the life of the machine, not worth
/// repeating every second.
final class GPUMonitor {

    private var name: String?
    private var didResolveName = false

    func sample() -> GPUStats? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }

            guard let stats = IORegistryEntryCreateCFProperty(
                entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] else { continue }

            // Only the real accelerator publishes a utilisation figure; skip
            // any other IOAccelerator nodes that don't.
            guard let utilization = Self.number(stats["Device Utilization %"]) else { continue }

            if !didResolveName {
                name = Self.registryName(entry)
                didResolveName = true
            }

            return GPUStats(
                name: name,
                utilization: utilization,
                rendererUtilization: Self.number(stats["Renderer Utilization %"]),
                tilerUtilization: Self.number(stats["Tiler Utilization %"]),
                inUseMemory: Self.number(stats["In use system memory"]).map { Int64($0) },
                allocatedMemory: Self.number(stats["Alloc system memory"]).map { Int64($0) }
            )
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func registryName(_ entry: io_registry_entry_t) -> String? {
        // The accelerator node itself is named things like "AGXAcceleratorG16".
        // The friendlier marketing name lives on its parent device.
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(parent) }

        if let model = IORegistryEntryCreateCFProperty(
            parent, "model" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() {
            if let data = model as? Data {
                return String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            }
            if let string = model as? String { return string }
        }
        return nil
    }
}
