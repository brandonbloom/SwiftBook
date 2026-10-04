import SwiftUI

/// Reads previews into stories. The only code that depends on the private structure of
/// DeveloperToolsSupport's `Preview`, together with ``PreviewBody``, ``PreviewGroup``,
/// ``PreviewModifiers`` and ``Reflection``.
///
/// Every assumption about that structure is checked. A preview that doesn't match yields a story
/// whose `makeView()` throws ``AdapterError``, so an SDK change fails loudly instead of rendering
/// the wrong thing.
@MainActor enum PreviewAdapter {
    /// A story before its identity is assigned.
    struct Draft {
        let module: String
        let group: String
        let displayName: String?
        let fileID: String?
        let line: Int?
        var layout = StoryLayout.device
        var orientation: StoryOrientation?
        let make: @MainActor () async throws -> AnyView
    }

    static func drafts(for preview: DiscoveredPreview) -> [Draft] {
        switch preview.source {
        case .registry(let registry):
            let location = "\(registry.fileID):\(registry.line)"
            let group = StoryID.group(forFileID: registry.fileID)
            let made: Preview
            do {
                made = try registry.makePreview()
            } catch is PreviewUnavailable {
                return []
            } catch {
                return [failed(preview, group: group, displayName: nil, error: error)]
            }
            return drafts(
                from: made, module: preview.module, group: group, fileID: registry.fileID,
                line: registry.line,
                location: location)
        case .provider(let provider):
            return drafts(
                fromProvider: provider, module: preview.module, group: preview.providerName ?? "")
        }
    }

    // MARK: `#Preview`

    static func drafts(
        from preview: Preview, module: String, group: String, fileID: String?, line: Int?,
        location: String
    ) -> [Draft] {
        let mirror = Mirror(reflecting: preview)
        // Read the name first, so a preview that fails later still gets its identity.
        let displayName = mirror.optionalString("displayName") ?? nil
        func failure(_ error: Error) -> Draft {
            Draft(
                module: module, group: group, displayName: displayName, fileID: fileID, line: line,
                make: { throw (error as? AdapterError)?.at(location) ?? error })
        }
        do {
            guard mirror.optionalString("displayName") != nil else {
                throw AdapterError.unexpectedShape("Preview has no displayName")
            }
            let traits = try Traits(mirror.descendant("traits"))
            return try PreviewBody.bodies(of: mirror.descendant("dataSource")).map { body in
                // Each argument of a `#Preview(arguments:)` is its own story, "<preview> / <label>".
                let name = body.label.map { "\(displayName ?? group) / \($0)" } ?? displayName
                var draft = Draft(
                    module: module, group: group, displayName: name, fileID: fileID, line: line,
                    make: {
                        do {
                            var view = try body.makeView()
                            for modifier in traits.modifiers {
                                view = try await PreviewModifiers.apply(modifier, to: view)
                            }
                            return view
                        } catch let error as AdapterError {
                            throw error.at(location)
                        }
                    })
                draft.layout = traits.layout
                draft.orientation = traits.orientation
                return draft
            }
        } catch {
            return [failure(error)]
        }
    }

    private static func failed(
        _ preview: DiscoveredPreview, group: String, displayName: String?, error: Error
    )
        -> Draft
    {
        Draft(
            module: preview.module, group: group, displayName: displayName, fileID: preview.fileID,
            line: preview.line, make: { throw error })
    }

    /// The traits SwiftBook understands. Any other trait is an error: rendering without it would
    /// silently differ from Xcode.
    struct Traits {
        var layout = StoryLayout.device
        var orientation: StoryOrientation?
        var modifiers: [any PreviewModifier] = []

        init(_ traits: Any?) throws {
            guard let traits else { throw AdapterError.unexpectedShape("Preview has no traits") }
            for trait in Mirror(reflecting: traits).children.map(\.value) {
                let kind = String(describing: type(of: trait))
                let value = Mirror(reflecting: trait).descendant("value")
                switch kind {
                case "PreviewLayoutTrait":
                    guard let value = value as? PreviewLayout else {
                        throw AdapterError.unexpectedShape(
                            "PreviewLayoutTrait value is \(Swift.type(of: value))")
                    }
                    layout = try StoryLayout(value)
                case "PreviewInterfaceOrientationTrait":
                    let name = value.map { String(describing: $0) } ?? ""
                    guard let parsed = StoryOrientation(rawValue: name) else {
                        throw AdapterError.unexpectedShape("unknown interface orientation \(name)")
                    }
                    orientation = parsed
                case "PreviewModifierTrait":
                    guard let value = value as? [any PreviewModifier] else {
                        throw AdapterError.unexpectedShape(
                            "PreviewModifierTrait value is \(Swift.type(of: value))")
                    }
                    modifiers += value
                default:
                    throw AdapterError.unsupported("preview trait \(kind)")
                }
            }
        }
    }

    // MARK: `PreviewProvider`

    static func drafts(
        fromProvider provider: any PreviewProvider.Type, module: String, group: String
    ) -> [Draft] {
        provider._allPreviews.enumerated().map { index, preview in
            let layout: StoryLayout
            do {
                layout = try StoryLayout(preview.layout)
            } catch {
                return Draft(
                    module: module, group: group, displayName: preview.displayName, fileID: nil,
                    line: nil,
                    make: { throw error })
            }
            var draft = Draft(
                module: module, group: group, displayName: preview.displayName, fileID: nil,
                line: nil,
                make: {
                    // `_allPreviews` builds fresh content on every access.
                    let previews = provider._allPreviews
                    guard previews.indices.contains(index) else {
                        throw AdapterError.unexpectedShape(
                            "\(group) no longer has a preview \(index)")
                    }
                    return previews[index].content
                })
            draft.layout = layout
            // Every legacy preview reports an orientation; portrait is the default.
            draft.orientation = StoryOrientation(preview.interfaceOrientation)
            return draft
        }
    }
}

extension StoryLayout {
    init(_ layout: PreviewLayout) throws {
        switch layout {
        case .device: self = .device
        case .sizeThatFits: self = .sizeThatFits
        case .fixed(let width, let height): self = .fixed(width: width, height: height)
        case .fixed3D: throw AdapterError.unsupported("visionOS layout fixed3D")
        @unknown default: throw AdapterError.unsupported("layout \(layout)")
        }
    }
}

extension StoryOrientation {
    /// The orientation a legacy preview asks for, or `nil` for the default portrait.
    init?(_ orientation: InterfaceOrientation) {
        switch orientation {
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}
