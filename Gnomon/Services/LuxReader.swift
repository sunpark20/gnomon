import Foundation
import IOKit

/// Reads the ambient light value published by the built-in display driver.
public struct LuxReader: Sendable {
    public enum ReadError: Error, LocalizedError {
        case serviceNotFound
        case propertyNotFound
        case invalidReading

        public var errorDescription: String? {
            switch self {
            case .serviceNotFound: "Built-in display sensor service not found"
            case .propertyNotFound: "AmbientBrightness property not found"
            case .invalidReading: "Invalid ambient light sensor value"
            }
        }
    }

    public init() {}

    public func currentLux() async throws -> Double {
        try Task.checkCancellation()
        guard let matching = IOServiceMatching("IOMobileFramebufferShim") else {
            throw ReadError.serviceNotFound
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            throw ReadError.serviceNotFound
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            guard Self.isBuiltIn(service) else { continue }
            let value = IORegistryEntryCreateCFProperty(
                service, "AmbientBrightness" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue()
            return try Self.decodeLux(value)
        }
        throw ReadError.serviceNotFound
    }

    private static func isBuiltIn(_ service: io_service_t) -> Bool {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(parent) }
        let name = IORegistryEntryCreateCFProperty(
            parent, "name" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Data
        // The IODeviceTree name is NUL-terminated data.
        return name?.prefix(while: { $0 != 0 }).elementsEqual("disp0".utf8) == true
    }

    static func decodeLux(_ value: CFTypeRef?) throws -> Double {
        guard let value else { throw ReadError.propertyNotFound }
        guard CFGetTypeID(value) == CFNumberGetTypeID(), let number = value as? NSNumber,
              let raw = UInt32(exactly: number.doubleValue) else { throw ReadError.invalidReading }
        return Double(raw) / 65536
    }
}
