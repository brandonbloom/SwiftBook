import Darwin

/// Low-level access to Swift runtime metadata, for reading values of types the SDK doesn't expose.
///
/// Runtime entry points are looked up with `dlsym` rather than `@_silgen_name`, because the
/// compiler reserves `swift_*` names. Each lookup is checked; a missing symbol becomes an
/// `AdapterError`, never a crash.
enum Reflection {
    struct Field {
        let name: String
        let offset: Int
        let type: Any.Type
    }

    /// The stored fields of a struct, class, enum payload, or tuple type, from its metadata.
    static func fields(of type: Any.Type) throws -> [Field] {
        let runtime = try Runtime.shared()
        let typeMetadata = pointer(to: type)
        return (0..<runtime.count(typeMetadata)).map { index in
            var metadata = FieldMetadata()
            let fieldType = withUnsafeMutablePointer(to: &metadata) {
                runtime.childMetadata(typeMetadata, index, UnsafeMutableRawPointer($0))
            }
            defer { metadata.freeFunc?(metadata.name) }
            return Field(
                name: metadata.name.map { String(cString: $0) } ?? "",
                offset: runtime.childOffset(typeMetadata, index),
                type: unsafeBitCast(fieldType, to: Any.Type.self))
        }
    }

    /// A function type's parameter and result types.
    static func signature(ofFunction value: Any) throws -> (
        parameters: [Any.Type], result: Any.Type
    ) {
        // TargetFunctionTypeMetadata: kind, flags, result type, then one pointer per parameter.
        let metadata = pointer(to: type(of: value))
        guard metadata.load(as: Int.self) == functionMetadataKind else {
            throw AdapterError.unexpectedShape("\(type(of: value)) is not a function type")
        }
        // TargetFunctionTypeFlags: parameter count, convention, then throws/escaping/actor bits.
        let flags = metadata.load(fromByteOffset: 8, as: Int.self)
        let swiftConvention = flags & 0xFF_0000 == 0
        let throwsOrAsync = flags & (0x0100_0000 | 0x2000_0000) != 0
        guard swiftConvention, !throwsOrAsync else {
            throw AdapterError.unexpectedShape(
                "\(type(of: value)) has function flags \(String(flags, radix: 16))")
        }
        let parameterCount = flags & 0xFFFF
        let result = metadata.load(fromByteOffset: 16, as: Any.Type.self)
        let parameters = (0..<parameterCount).map {
            metadata.load(fromByteOffset: 24 + 8 * $0, as: Any.Type.self)
        }
        return (parameters, result)
    }

    /// Reinterprets a synchronous, nonthrowing Swift closure as function type `F`.
    ///
    /// Swift 6 won't dynamically cast closures across global-actor isolation, so a main-actor
    /// closure of a private type can't be cast to a callable type. Isolation doesn't change a
    /// synchronous closure's representation, so once ``signature(ofFunction:)`` has confirmed the
    /// parameter and result types, the closure can be reinterpreted.
    static func function<F>(_ value: Any, as _: F.Type) throws -> F {
        guard size(of: type(of: value)) == MemoryLayout<F>.size else {
            throw AdapterError.unexpectedShape("\(type(of: value)) isn't a closure like \(F.self)")
        }
        func reinterpret<V>(_ value: V) -> F { unsafeBitCast(value, to: F.self) }
        return _openExistential(value, do: reinterpret)
    }

    /// The address of a type's metadata.
    static func pointer(to type: Any.Type) -> UnsafeRawPointer {
        unsafeBitCast(type, to: UnsafeRawPointer.self)
    }

    /// The size in bytes of a value of `type`.
    static func size(of type: Any.Type) -> Int {
        func size<T>(_: T.Type) -> Int { MemoryLayout<T>.size }
        return _openExistential(type, do: size)
    }

    /// Looks up a symbol exported by a loaded image.
    static func symbol(_ name: String) throws -> UnsafeMutableRawPointer {
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else {
            throw AdapterError.missingSymbol(name)
        }
        return address
    }

    /// `MetadataKind::Function`.
    private static let functionMetadataKind = 0x302

    /// Mirrors the runtime's `FieldReflectionMetadata`.
    private struct FieldMetadata {
        var name: UnsafePointer<CChar>?
        var freeFunc: (@convention(c) (UnsafePointer<CChar>?) -> Void)?
        var isStrong = false
        var isVar = false
    }

    /// The runtime's reflection entry points, which back the standard library's `Mirror`.
    private struct Runtime: @unchecked Sendable {
        // These are Swift-convention functions; on arm64 their register use for pointer and
        // integer arguments matches the C convention.
        let count: @convention(c) (UnsafeRawPointer) -> Int
        let childMetadata:
            @convention(c) (UnsafeRawPointer, Int, UnsafeMutableRawPointer) -> UnsafeRawPointer
        let childOffset: @convention(c) (UnsafeRawPointer, Int) -> Int

        private static let loaded = Result {
            Runtime(
                count: unsafeBitCast(
                    try symbol("swift_reflectionMirror_recursiveCount"),
                    to: (@convention(c) (UnsafeRawPointer) -> Int).self),
                childMetadata: unsafeBitCast(
                    try symbol("swift_reflectionMirror_recursiveChildMetadata"),
                    to: (@convention(c) (UnsafeRawPointer, Int, UnsafeMutableRawPointer) ->
                        UnsafeRawPointer)
                        .self),
                childOffset: unsafeBitCast(
                    try symbol("swift_reflectionMirror_recursiveChildOffset"),
                    to: (@convention(c) (UnsafeRawPointer, Int) -> Int).self))
        }

        static func shared() throws -> Runtime { try loaded.get() }
    }
}

extension Mirror {
    /// Reads a stored `String?` child: `nil` if the child is missing or isn't a `String?`,
    /// `.some(nil)` if it holds no string.
    ///
    /// Casting `Any` to `String?` doesn't reliably distinguish those cases, so this inspects the
    /// optional's own mirror.
    func optionalString(_ label: String) -> String?? {
        guard let value = descendant(label) else { return nil }
        let optional = Mirror(reflecting: value)
        guard optional.displayStyle == .optional, type(of: value) == String?.self else {
            return nil
        }
        return .some(optional.children.first?.value as? String)
    }
}
