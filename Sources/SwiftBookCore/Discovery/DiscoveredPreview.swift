import SwiftUI

/// A preview found in the running process, before its contents are read.
package struct DiscoveredPreview: @unchecked Sendable {
    // Unchecked: metatypes are immutable, but the conformances' main-actor isolation keeps the
    // compiler from proving these are Sendable.

    /// Where a preview was declared.
    package enum Source {
        /// A `#Preview`, which expands to a type conforming to `PreviewRegistry`.
        case registry(any PreviewRegistry.Type)
        /// A type conforming to the legacy `PreviewProvider` protocol.
        case provider(any PreviewProvider.Type)
    }

    package let source: Source
    /// The module that declares the preview.
    package let module: String
    /// The declaring file as `Module/File.swift`, for `#Preview`. Unknown for `PreviewProvider`.
    package let fileID: String?
    /// The 1-based line of the `#Preview`. Unknown for `PreviewProvider`.
    package let line: Int?
    /// The 1-based column of the `#Preview`. Unknown for `PreviewProvider`.
    package let column: Int?
    /// The `PreviewProvider` type's name, for legacy previews.
    package let providerName: String?
}

extension DiscoveredPreview {
    /// Finds every preview in the images loaded into this process.
    ///
    /// Results are sorted by module, then by `#Preview` source location, then by `PreviewProvider`
    /// type name, so the order is stable across runs.
    package static func all() -> [DiscoveredPreview] {
        let matches = ConformanceScanner.scan(protocolNames: ["PreviewRegistry", "PreviewProvider"])
        let previews = matches.compactMap { match -> DiscoveredPreview? in
            // The cast, not the name check, is authoritative: another module may declare a
            // protocol with the same name.
            if let registry = match.type as? any PreviewRegistry.Type {
                return DiscoveredPreview(registry: registry)
            }
            if let provider = match.type as? any PreviewProvider.Type {
                return DiscoveredPreview(provider: provider)
            }
            return nil
        }
        return previews.sorted { $0.precedes($1) }
    }

    init(registry: any PreviewRegistry.Type) {
        let fileID = registry.fileID
        self.init(
            source: .registry(registry),
            module: String(fileID.prefix { $0 != "/" }),
            fileID: fileID,
            line: registry.line,
            column: registry.column,
            providerName: nil)
    }

    init(provider: any PreviewProvider.Type) {
        // `String(reflecting:)` gives the fully qualified name, such as `Module.Outer.Provider`.
        let qualified = String(reflecting: provider)
        let module = String(qualified.prefix { $0 != "." })
        self.init(
            source: .provider(provider),
            module: module,
            fileID: nil,
            line: nil,
            column: nil,
            providerName: String(qualified.dropFirst(module.count + 1)))
    }

    private func precedes(_ other: DiscoveredPreview) -> Bool {
        // Within a module, `#Preview`s (which have a file) sort before `PreviewProvider`s.
        func key(_ p: DiscoveredPreview) -> (String, Int, String, Int, Int, String) {
            (
                p.module, p.fileID == nil ? 1 : 0, p.fileID ?? "", p.line ?? 0, p.column ?? 0,
                p.providerName ?? ""
            )
        }
        return key(self) < key(other)
    }
}
