import SwiftUI

/// A parameterized `#Preview(arguments:)`: the items its metadata describes, and the closure that
/// builds any one of them.
///
/// DeveloperToolsSupport stores the group as `(metadata: PreviewGroupMetadata, makeBody)`, where
/// `makeBody` is `@MainActor (PreviewGroupIndex?) -> (Body, PreviewGroupIndex)`: it builds the
/// item at an index (the first, for `nil`) and returns that index. The metadata lists sections,
/// each with a title, an item count, and one description per item.
@MainActor struct PreviewGroup {
    /// `PreviewGroupIndex`'s layout.
    struct Index: Equatable {
        var section: Int
        var preview: Int
    }

    struct Item {
        let index: Index
        /// The item's description from the metadata, prefixed by its section's title if any.
        /// An item without a description is numbered within its section, from 1.
        let label: String
    }

    let items: [Item]
    private let makeBody: Any
    /// The `Body` type `makeBody` returns.
    private let bodyType: Any.Type

    init(metadata: Any, makeBody: Any) throws {
        items = try Self.items(from: metadata)
        self.makeBody = makeBody
        bodyType = try Self.checkShape(of: makeBody)
    }

    /// Builds the item at `index`, before preview modifiers.
    func makeView(at index: Index) throws -> AnyView {
        func call<Body>(_: Body.Type) throws -> AnyView {
            // Runs on the main actor, as `makeBody` requires.
            let (body, built): (Body, Index) = try Self.call(makeBody, at: index as Index?)
            guard built == index else {
                throw AdapterError.unexpectedShape(
                    "preview group built item \(built) when asked for \(index)")
            }
            return try PreviewBody.view(from: body)
        }
        return try _openExistential(bodyType, do: call)
    }

    // MARK: Calling the closure

    /// A stored closure with the group closure's calling convention: the index passed indirectly,
    /// and the body and the built index each returned indirectly.
    ///
    /// Stored properties are laid out for their declared types, so `makeBody` here passes its
    /// generic index and results indirectly. DeveloperToolsSupport's closure does the same, because
    /// its index type is resilient. `Reflection.function(_:as:)` can't express this: a function
    /// held in a generic parameter returns a tuple as one value, not as two.
    private struct Shadow<Argument, Body, Built> {
        let makeBody: (Argument) -> (Body, Built)
    }

    /// Calls the group closure. Generic in every position so that the call matches ``Shadow``'s
    /// convention, whatever the caller's concrete types.
    private static func call<Argument, Body, Built>(_ makeBody: Any, at argument: Argument) throws
        -> (Body, Built)
    {
        let size = MemoryLayout<Shadow<Argument, Body, Built>>.size
        guard Reflection.size(of: type(of: makeBody)) == size else {
            throw AdapterError.unexpectedShape("\(type(of: makeBody)) isn't a closure")
        }
        func reinterpret<V>(_ value: V) -> Shadow<Argument, Body, Built> {
            unsafeBitCast(value, to: Shadow<Argument, Body, Built>.self)
        }
        return _openExistential(makeBody, do: reinterpret).makeBody(argument)
    }

    /// Checks `makeBody`'s signature against the runtime metadata and returns its `Body` type.
    private static func checkShape(of makeBody: Any) throws -> Any.Type {
        let signature = try Reflection.signature(ofFunction: makeBody)
        let results = try Reflection.fields(of: signature.result)
        guard signature.parameters.count == 1, results.count == 2,
            Reflection.size(of: signature.result) == results[1].offset + MemoryLayout<Index>.size
        else {
            throw AdapterError.unexpectedShape("preview group makeBody is \(type(of: makeBody))")
        }
        let indexType = results[1].type
        guard String(describing: indexType) == "PreviewGroupIndex" else {
            throw AdapterError.unexpectedShape("preview group index is \(indexType)")
        }
        try PreviewBody.checkLayout(of: indexType, matches: Index.self)
        func optional<T>(_: T.Type) -> Any.Type { T?.self }
        guard signature.parameters[0] == _openExistential(indexType, do: optional) else {
            throw AdapterError.unexpectedShape(
                "preview group makeBody takes \(signature.parameters[0])")
        }
        return results[0].type
    }

    // MARK: Reading the metadata

    private static func items(from metadata: Any) throws -> [Item] {
        // PreviewGroupMetadata { firstSection: Section, moreSections: [Section] }
        let mirror = Mirror(reflecting: metadata)
        guard let first = mirror.descendant("firstSection"),
            let more = mirror.descendant("moreSections")
        else {
            throw AdapterError.unexpectedShape(
                "preview group metadata is \(type(of: metadata))")
        }
        let sections = [first] + Mirror(reflecting: more).children.map(\.value)
        return try sections.enumerated().flatMap { section, value in
            try items(inSection: section, value)
        }
    }

    private static func items(inSection section: Int, _ value: Any) throws -> [Item] {
        // Section { title: String?, previewCount: Int, itemDescriptions: [String?] }
        let mirror = Mirror(reflecting: value)
        guard let title = mirror.optionalString("title"),
            let count = mirror.descendant("previewCount") as? Int,
            let descriptions = mirror.descendant("itemDescriptions") as? [String?],
            descriptions.count == count
        else {
            throw AdapterError.unexpectedShape("preview group section is \(type(of: value))")
        }
        return descriptions.enumerated().map { preview, description in
            let name = description ?? String(preview + 1)
            return Item(
                index: Index(section: section, preview: preview),
                label: title.map { "\($0) / \(name)" } ?? name)
        }
    }
}
