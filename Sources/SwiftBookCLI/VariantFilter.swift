#if os(macOS)
    import ArgumentParser
    import SwiftBookCore

    /// Which references to include, by their variant's device and appearance.
    struct VariantFilter {
        /// The devices to include, or every device if empty.
        var devices: [Device]
        /// The appearance to include, or both if `nil`.
        var appearance: RenderEnvironment.Appearance?

        /// Whether to include a reference whose variant file name is `variant`, such as
        /// `iphone.dark` or `mac.light.rtl`.
        func includes(_ variant: String) -> Bool {
            let parts = variant.split(separator: ".").map(String.init)
            guard parts.count >= 2 else { return devices.isEmpty && appearance == nil }
            if !devices.isEmpty, !devices.contains(where: { $0.rawValue == parts[0] }) {
                return false
            }
            if let appearance, appearance.rawValue != parts[1] { return false }
            return true
        }
    }

    extension RenderEnvironment.Appearance: ExpressibleByArgument {}
#endif
