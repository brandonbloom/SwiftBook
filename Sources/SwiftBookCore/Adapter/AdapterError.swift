import Foundation

/// The preview adapter couldn't read a preview, almost always because an Xcode or SDK update
/// changed the private internals it depends on.
///
/// Never swallowed: a story that can't be read fails loudly wherever it's rendered.
public struct AdapterError: Error, CustomStringConvertible, Sendable {
    public let problem: String
    /// Where the preview is declared, when known: `Module/File.swift:line`.
    public var location: String?

    static func unexpectedShape(_ problem: String) -> AdapterError {
        AdapterError(problem: "unexpected shape: \(problem)")
    }

    static func unsupported(_ problem: String) -> AdapterError {
        AdapterError(problem: "unsupported: \(problem)")
    }

    static func missingSymbol(_ name: String) -> AdapterError {
        AdapterError(problem: "missing runtime symbol \(name)")
    }

    func at(_ location: String?) -> AdapterError {
        var error = self
        error.location = error.location ?? location
        return error
    }

    public var description: String {
        """
        SwiftBook couldn't read the preview\(location.map { " at \($0)" } ?? ""): \(problem).
        This usually means an Xcode or SDK release changed the private structure of previews, which \
        SwiftBook's preview adapter reads. Environment: \(Self.environment).
        """
    }

    /// The OS and framework versions, which identify the SDK whose internals were read.
    static var environment: String {
        let info = ProcessInfo.processInfo
        let frameworks = ["com.apple.SwiftUI", "com.apple.DeveloperToolsSupport"].map {
            identifier in
            let version = Bundle(identifier: identifier)?.object(
                forInfoDictionaryKey: "CFBundleVersion")
            return "\(identifier.split(separator: ".").last!) \(version as? String ?? "unknown")"
        }
        return ([info.operatingSystemVersionString] + frameworks).joined(separator: ", ")
    }
}
