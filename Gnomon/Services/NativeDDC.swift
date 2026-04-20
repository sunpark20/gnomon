//
//  NativeDDC.swift
//  Gnomon
//
//  Native DDC/CI over IOAVService for Apple Silicon.
//  Replaces shell-out to m1ddc.
//

import Foundation
import IOKit

// MARK: - Private IOAVService API

@_silgen_name("IOAVServiceCreateWithService")
private func _AVServiceCreateWithService(
    _ allocator: CFAllocator?, _ service: io_service_t
) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOAVServiceReadI2C")
private func _AVServiceReadI2C(
    _ service: CFTypeRef, _ chipAddress: UInt32, _ offset: UInt32,
    _ output: UnsafeMutablePointer<UInt8>, _ outputSize: UInt32
) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
private func _AVServiceWriteI2C(
    _ service: CFTypeRef, _ chipAddress: UInt32, _ offset: UInt32,
    _ input: UnsafeMutablePointer<UInt8>, _ inputSize: UInt32
) -> IOReturn

// MARK: - DDC Protocol Constants

private let i2cAddress: UInt32 = 0x37
private let hostAddr: UInt8 = 0x51
private let displayAddr: UInt8 = 0x6E

enum VCPCode: UInt8 {
    case brightness = 0x10
    case contrast = 0x12
}

// MARK: - NativeDDC

enum NativeDDC {
    struct DisplayInfo {
        let entryID: UInt64
        let name: String
    }

    static func discoverDisplays() -> [DisplayInfo] {
        guard let matching = IOServiceMatching("DCPAVServiceProxy") else {
            print("[NativeDDC] IOServiceMatching returned nil")
            return []
        }
        var iterator: io_iterator_t = 0
        let matchResult = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard matchResult == kIOReturnSuccess else {
            print("[NativeDDC] IOServiceGetMatchingServices failed: \(matchResult)")
            return []
        }
        defer { IOObjectRelease(iterator) }

        var displays: [DisplayInfo] = []
        var entryCount = 0
        var entry = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            entryCount += 1

            var entryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(entry, &entryID) == kIOReturnSuccess else {
                print("[NativeDDC] entry \(entryCount): failed to get registry entry ID")
                continue
            }

            guard let ref = _AVServiceCreateWithService(kCFAllocatorDefault, entry) else {
                print("[NativeDDC] entry \(entryCount) (id=\(entryID)): IOAVServiceCreateWithService returned nil")
                continue
            }
            let service = ref.takeRetainedValue()

            var brightness: Int?
            for attempt in 1 ... 3 {
                brightness = readVCPRaw(.brightness, service: service)
                if brightness != nil { break }
                if attempt < 3 { usleep(50000) }
            }
            guard let brightness else {
                print("[NativeDDC] entry \(entryCount) (id=\(entryID)): DDC brightness read failed (built-in display?)")
                continue
            }

            let name = productName(for: entry) ?? "External Display"
            print("[NativeDDC] entry \(entryCount) (id=\(entryID)): \(name), brightness=\(brightness)")
            displays.append(DisplayInfo(entryID: entryID, name: name))
        }
        print("[NativeDDC] found \(entryCount) DCPAVServiceProxy entries, \(displays.count) DDC displays")
        return displays
    }

    static func readVCP(_ code: VCPCode, entryID: UInt64) -> Int? {
        guard let service = avService(for: entryID) else { return nil }
        return readVCPRaw(code, service: service)
    }

    @discardableResult
    static func writeVCP(_ code: VCPCode, value: Int, entryID: UInt64) -> Bool {
        guard let service = avService(for: entryID) else { return false }
        return writeVCPRaw(code, value: value, service: service)
    }

    // MARK: - Service Lookup

    private static func avService(for entryID: UInt64) -> CFTypeRef? {
        guard let matching = IORegistryEntryIDMatching(entryID) else { return nil }
        let ioService = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard ioService != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(ioService) }
        return _AVServiceCreateWithService(kCFAllocatorDefault, ioService)?.takeRetainedValue()
    }

    // MARK: - Raw I2C

    private static func readVCPRaw(_ code: VCPCode, service: CFTypeRef) -> Int? {
        var request: [UInt8] = [0x82, 0x01, code.rawValue]
        var checksum: UInt8 = displayAddr ^ hostAddr
        for b in request {
            checksum ^= b
        }
        request.append(checksum)

        let wr = _AVServiceWriteI2C(service, i2cAddress, UInt32(hostAddr), &request, UInt32(request.count))
        if wr != kIOReturnSuccess {
            print("[NativeDDC]   writeI2C failed: 0x\(String(wr, radix: 16))")
            return nil
        }

        usleep(40000)

        var reply = [UInt8](repeating: 0, count: 11)
        let rd = _AVServiceReadI2C(service, i2cAddress, UInt32(hostAddr), &reply, UInt32(reply.count))
        if rd != kIOReturnSuccess {
            print("[NativeDDC]   readI2C failed: 0x\(String(rd, radix: 16))")
            return nil
        }

        // reply[0]=source(0x6E) [1]=length [2]=opcode(0x02) [3]=result [4]=vcp
        // reply[6..7]=max(big-endian) reply[8..9]=current(big-endian) [10]=checksum
        guard reply[2] == 0x02, reply[3] == 0x00 else { return nil }

        return Int(reply[8]) << 8 | Int(reply[9])
    }

    private static func writeVCPRaw(_ code: VCPCode, value: Int, service: CFTypeRef) -> Bool {
        let v = UInt16(clamping: max(0, min(value, 100)))
        var data: [UInt8] = [0x84, 0x03, code.rawValue, UInt8(v >> 8), UInt8(v & 0xFF)]
        var checksum: UInt8 = displayAddr ^ hostAddr
        for b in data {
            checksum ^= b
        }
        data.append(checksum)

        return _AVServiceWriteI2C(service, i2cAddress, UInt32(hostAddr), &data, UInt32(data.count)) == kIOReturnSuccess
    }

    // MARK: - Display Name

    private static func productName(for entry: io_service_t) -> String? {
        guard let value = IORegistryEntrySearchCFProperty(
            entry,
            kIOServicePlane,
            "DisplayProductName" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        ) else { return nil }
        guard let nameDict = value as? [String: String] else { return nil }
        return nameDict["en_US"] ?? nameDict.values.first
    }
}
