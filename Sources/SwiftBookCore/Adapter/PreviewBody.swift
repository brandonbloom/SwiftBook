import SwiftUI

/// The content of a `#Preview`, from its data source.
@MainActor struct PreviewBody {
    /// Builds the preview's view, before preview modifiers.
    let makeView: @MainActor () throws -> AnyView

    init(_ dataSource: Any?) throws {
        // DataSource is an enum; `.preview(source)` holds a DefaultPreviewSource<Body>.
        guard let dataSource, let source = Mirror(reflecting: dataSource).children.first else {
            throw AdapterError.unexpectedShape("Preview has no dataSource")
        }
        guard source.label == "preview" else {
            throw AdapterError.unsupported("preview data source \(source.label ?? "?")")
        }
        guard let structure = Mirror(reflecting: source.value).descendant("structure"),
            let kind = Mirror(reflecting: structure).children.first
        else {
            throw AdapterError.unexpectedShape(
                "preview source \(type(of: source.value)) has no structure")
        }
        switch kind.label {
        case "singlePreview":
            let makeBody = Mirror(reflecting: kind.value).descendant("makeBody") ?? kind.value
            makeView = { try Self.call(makeBody) }
        case "previewGroup":
            // Parameterized `#Preview(arguments:)`. Calling its group closure through `Mirror`
            // crashes inside DeveloperToolsSupport (see `preview-arguments` in docs/plan.md), so
            // these fail loudly until it's supported.
            throw AdapterError.unsupported("parameterized #Preview(arguments:)")
        default:
            throw AdapterError.unsupported("preview structure \(kind.label ?? "?")")
        }
    }

    // MARK: Calling bodies
    //
    // A body closure can't be dynamically cast to a callable type: its result type may be private,
    // and Swift 6 won't cast across global-actor isolation. So, after checking its signature
    // against the runtime metadata, the closure is reinterpreted as a function type with the same
    // calling convention.
    //
    // `Mirror` hands the closure over boxed in `Any`, which stores functions at maximal
    // abstraction: every parameter and result passed opaquely. The reinterpreted type must match,
    // so its types are generic parameters, never concrete types. (A concrete type here crashes.)

    /// `ViewPreviewBody`'s layout.
    private struct RawViewBody {
        var body: any View
    }

    /// Calls a single preview's `makeBody() -> Body`.
    private static func call(_ makeBody: Any) throws -> AnyView {
        let signature = try Reflection.signature(ofFunction: makeBody)
        guard signature.parameters.isEmpty else {
            throw AdapterError.unexpectedShape("preview makeBody is \(type(of: makeBody))")
        }
        func call<Body>(_: Body.Type) throws -> AnyView {
            // Runs on the main actor, as `makeBody` requires.
            try view(from: try Reflection.function(makeBody, as: (() -> Body).self)())
        }
        return try _openExistential(signature.result, do: call)
    }

    /// The view a body holds: a ViewPreviewBody's SwiftUI view, or a platform view or controller.
    private static func view<Body>(from body: Body) throws -> AnyView {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
            if let view = body as? NSView { return PlatformViews.wrap(view) }
            if let controller = body as? NSViewController { return PlatformViews.wrap(controller) }
        #elseif canImport(UIKit)
            if let view = body as? UIView { return PlatformViews.wrap(view) }
            if let controller = body as? UIViewController { return PlatformViews.wrap(controller) }
        #endif
        try checkLayout(of: Body.self, matches: RawViewBody.self)
        return AnyView(unsafeBitCast(body, to: RawViewBody.self).body)
    }

    /// Checks that `actual` stores the same fields, by name, offset, and type, as `shadow`, so a
    /// value of one can be reinterpreted as the other.
    nonisolated private static func checkLayout(of actual: Any.Type, matches shadow: Any.Type)
        throws
    {
        let actualFields = try Reflection.fields(of: actual)
        let shadowFields = try Reflection.fields(of: shadow)
        let matches =
            actualFields.count == shadowFields.count
            && zip(actualFields, shadowFields).allSatisfy { actual, shadow in
                actual.name == shadow.name && actual.offset == shadow.offset
                    && actual.type == shadow.type
            }
            && Reflection.size(of: actual) == Reflection.size(of: shadow)
        guard matches else {
            let description = actualFields.map { "\($0.name)@\($0.offset): \($0.type)" }.joined(
                separator: ", ")
            throw AdapterError.unexpectedShape(
                "\(actual) has fields [\(description)], expected \(shadow)")
        }
    }
}
