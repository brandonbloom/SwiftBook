import Foundation
import SwiftBook
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// The package's ``SwiftBookConfiguration``, found in the running process like its previews.
@MainActor public enum ProjectConfiguration {
    /// The declaring type, if the package declares one.
    public static let declaration: (any SwiftBookConfiguration.Type)? = {
        let declarations = ConformanceScanner.scan(protocolNames: ["SwiftBookConfiguration"])
            // The cast, not the name, is authoritative: another module may declare a protocol
            // with the same name.
            .compactMap { $0.type as? any SwiftBookConfiguration.Type }
            .sorted { String(reflecting: $0) < String(reflecting: $1) }
        if declarations.count > 1 {
            FileHandle.standardError.write(
                Data(
                    "swiftbook: several types conform to SwiftBookConfiguration (\(declarations.map { String(reflecting: $0) }.joined(separator: ", "))); using the first\n"
                        .utf8))
        }
        return declarations.first
    }()

    /// The tint around every story, if the package sets one.
    public static var tint: Color? { declaration?.tint }

    /// The tint as rendered in `appearance`, as `#RRGGBB` or `#RRGGBBAA`, for snapshot metadata.
    /// `nil` if the package sets none.
    static func tintDescription(in appearance: RenderEnvironment.Appearance) -> String? {
        guard let tint else { return nil }
        // Through the platform's color, with the appearance explicit: a color from an asset
        // catalog resolves against the current appearance, not SwiftUI's environment.
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        #if os(macOS)
            let named = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
            named?.performAsCurrentDrawingAppearance {
                NSColor(tint).usingColorSpace(.sRGB)?
                    .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            }
        #else
            UIColor(tint)
                .resolvedColor(
                    with: UITraitCollection(
                        userInterfaceStyle: appearance == .dark ? .dark : .light)
                )
                .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        func byte(_ component: CGFloat) -> String {
            String(format: "%02X", Int((min(max(component, 0), 1) * 255).rounded()))
        }
        let rgb = "#" + byte(red) + byte(green) + byte(blue)
        return alpha < 1 ? rgb + byte(alpha) : rgb
    }
}
