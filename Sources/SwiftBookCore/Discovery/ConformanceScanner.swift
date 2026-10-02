import MachO

/// Finds the types in loaded images that conform to protocols with given names.
///
/// Reads each image's `__TEXT,__swift5_proto` section of protocol conformance records, following
/// the Swift ABI's layouts for conformance, protocol, and type context descriptors. Images in the
/// dyld shared cache are skipped: they're system libraries, which hold no user previews.
enum ConformanceScanner {
    struct Match {
        let protocolName: String
        let type: Any.Type
    }

    static func scan(protocolNames: Set<String>) -> [Match] {
        var matches: [Match] = []
        for index in 0..<_dyld_image_count() {
            guard let header = _dyld_get_image_header(index),
                header.pointee.flags & MH_DYLIB_IN_CACHE == 0
            else { continue }
            var size: UInt = 0
            let section = header.withMemoryRebound(to: mach_header_64.self, capacity: 1) {
                getsectiondata($0, "__TEXT", "__swift5_proto", &size)
            }
            guard let section else { continue }
            let records = UnsafeRawPointer(section)
            // Each record is a 32-bit relative pointer to a protocol conformance descriptor.
            for offset in stride(from: 0, to: Int(size), by: 4) {
                if let match = match(
                    conformance: relative(records + offset), protocolNames: protocolNames)
                {
                    matches.append(match)
                }
            }
        }
        return matches
    }

    private static func match(conformance: UnsafeRawPointer, protocolNames: Set<String>) -> Match? {
        // Conformance descriptor: protocol (relative indirectable), type reference (relative),
        // witness table pattern (relative), flags (UInt32).
        let protocolDescriptor = relativeIndirectable(conformance)
        // Protocol descriptor: flags, parent, name (relative pointer to a C string), ...
        let protocolName = String(
            cString: relative(protocolDescriptor + 8).assumingMemoryBound(to: CChar.self))
        guard protocolNames.contains(protocolName) else { return nil }

        let flags = (conformance + 12).load(as: UInt32.self)
        let typeDescriptor: UnsafeRawPointer
        switch (flags >> 3) & 0x7 {
        case 0: typeDescriptor = relative(conformance + 4)
        case 1: typeDescriptor = relative(conformance + 4).load(as: UnsafeRawPointer.self)
        default: return nil  // Objective-C class references; previews are Swift types.
        }

        // Type context descriptor: flags, parent, name, metadata access function (relative), ...
        let contextFlags = typeDescriptor.load(as: UInt32.self)
        let kind = contextFlags & 0x1F
        let isGeneric = contextFlags & 0x80 != 0
        // Class, struct, and enum descriptors only. Generic types need arguments to instantiate,
        // and no preview type is generic.
        guard (16...18).contains(kind), !isGeneric else { return nil }

        typealias MetadataAccessor = @convention(c) (Int) -> UnsafeRawPointer
        let accessor = unsafeBitCast(relative(typeDescriptor + 12), to: MetadataAccessor.self)
        // Request 0 asks for complete metadata, blocking until it's available.
        let metadata = accessor(0)
        return Match(protocolName: protocolName, type: unsafeBitCast(metadata, to: Any.Type.self))
    }

    /// Follows a 32-bit relative pointer stored at `pointer`.
    private static func relative(_ pointer: UnsafeRawPointer) -> UnsafeRawPointer {
        pointer + Int(pointer.load(as: Int32.self))
    }

    /// Follows a relative pointer whose low bit marks an indirection through a pointer-sized slot.
    private static func relativeIndirectable(_ pointer: UnsafeRawPointer) -> UnsafeRawPointer {
        let offset = Int(pointer.load(as: Int32.self))
        let target = pointer + (offset & ~1)
        return offset & 1 == 0 ? target : target.load(as: UnsafeRawPointer.self)
    }
}
