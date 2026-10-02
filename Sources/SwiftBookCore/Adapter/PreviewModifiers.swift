import SwiftUI

/// Applies `PreviewModifier`s, which have no public way to be applied outside Xcode.
///
/// `PreviewModifier.body(content:context:)` takes a `PreviewModifierContent`, a placeholder that
/// only SwiftUI's internal `PreviewModifierViewModifier<M>` can fill. That type is exported but
/// not declared in the SDK, so this builds one from its metadata: it gets the type from its
/// metadata accessor, checks its stored fields match ``Shadow``, and reinterprets a `Shadow`.
@MainActor enum PreviewModifiers {
    /// Shared contexts by modifier type. Like Xcode, each is made once and reused across previews.
    private static var contexts: [ObjectIdentifier: Any] = [:]

    static func apply(_ modifier: any PreviewModifier, to content: AnyView) async throws -> AnyView
    {
        let viewModifierType = try viewModifierType(for: modifier)
        func apply<M: PreviewModifier>(_ modifier: M) async throws -> AnyView {
            let shadow = Shadow(modifier: modifier, context: try await context(for: M.self))
            try checkLayout(of: viewModifierType, matches: Shadow<M>.self)
            guard let viewModifierType = viewModifierType as? any ViewModifier.Type else {
                throw AdapterError.unexpectedShape("\(viewModifierType) is not a ViewModifier")
            }
            func modified<VM: ViewModifier>(_: VM.Type) -> AnyView {
                AnyView(content.modifier(unsafeBitCast(shadow, to: VM.self)))
            }
            return modified(viewModifierType)
        }
        return try await apply(modifier)
    }

    /// The expected layout of `PreviewModifierViewModifier<M>`.
    private struct Shadow<M: PreviewModifier> {
        var modifier: M
        var context: M.Context
    }

    private static func context<M: PreviewModifier>(for _: M.Type) async throws -> M.Context {
        if let context = contexts[ObjectIdentifier(M.self)] as? M.Context { return context }
        let context = try await M.makeSharedContext()
        contexts[ObjectIdentifier(M.self)] = context
        return context
    }

    /// `PreviewModifierViewModifier<M>`, for the dynamic type of `modifier`.
    private static func viewModifierType(for modifier: any PreviewModifier) throws -> Any.Type {
        typealias MetadataAccessor =
            @convention(c) (Int, UnsafeRawPointer, UnsafeRawPointer) -> UnsafeRawPointer
        typealias ConformsToProtocol =
            @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> UnsafeRawPointer?
        let accessor = unsafeBitCast(
            try Reflection.symbol("$s7SwiftUI019PreviewModifierViewD0VMa"),
            to: MetadataAccessor.self)
        let conformsToProtocol = unsafeBitCast(
            try Reflection.symbol("swift_conformsToProtocol"), to: ConformsToProtocol.self)
        let protocolDescriptor = try Reflection.symbol("$s7SwiftUI15PreviewModifierMp")
        let modifierType = Reflection.pointer(to: type(of: modifier))
        guard let witnessTable = conformsToProtocol(modifierType, protocolDescriptor) else {
            throw AdapterError.unexpectedShape(
                "\(type(of: modifier)) has no PreviewModifier witness table")
        }
        // A generic metadata accessor takes the request (0: complete metadata), then each generic
        // argument's metadata and witness tables.
        return unsafeBitCast(accessor(0, modifierType, witnessTable), to: Any.Type.self)
    }

    /// Checks that `actual` stores `_modifier` (a wrapper around `M`) then `context`, exactly as
    /// `Shadow<M>` lays them out.
    private static func checkLayout<M: PreviewModifier>(
        of actual: Any.Type, matches _: Shadow<M>.Type
    ) throws {
        let fields = try Reflection.fields(of: actual)
        let wrapped = try fields.first.map { try Reflection.fields(of: $0.type) } ?? []
        let matches =
            fields.map(\.name) == ["_modifier", "context"]
            && fields[0].offset == 0
            && wrapped.count == 1 && wrapped[0].offset == 0 && wrapped[0].type == M.self
            && Reflection.size(of: fields[0].type) == MemoryLayout<M>.size
            && fields[1].type == M.Context.self
            && fields[1].offset == MemoryLayout<Shadow<M>>.offset(of: \.context)
            && Reflection.size(of: actual) == MemoryLayout<Shadow<M>>.size
        guard matches else {
            let description = fields.map { "\($0.name)@\($0.offset): \($0.type)" }.joined(
                separator: ", ")
            throw AdapterError.unexpectedShape("\(actual) has fields [\(description)]")
        }
    }
}
