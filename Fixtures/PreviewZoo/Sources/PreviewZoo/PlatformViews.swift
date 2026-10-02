import SwiftUI

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    import AppKit

    /// An AppKit view, previewed directly with `#Preview`.
    final class ZooNSView: NSView {
        override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 60) }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemTeal.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        }
    }

    /// An AppKit view controller with a label.
    final class ZooNSViewController: NSViewController {
        override func loadView() {
            let label = NSTextField(labelWithString: "AppKit view controller")
            label.alignment = .center
            view = label
        }
    }

    #Preview("NSView") {
        ZooNSView()
    }

    #Preview("NSViewController") {
        ZooNSViewController()
    }
#endif

#if canImport(UIKit)
    import UIKit

    /// A UIKit view, previewed directly with `#Preview`.
    final class ZooUIView: UIView {
        override var intrinsicContentSize: CGSize { CGSize(width: 160, height: 60) }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .systemTeal
            layer.cornerRadius = 10
        }

        required init?(coder: NSCoder) { nil }
    }

    /// A UIKit view controller with a label.
    final class ZooUIViewController: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            let label = UILabel()
            label.text = "UIKit view controller"
            label.textAlignment = .center
            label.frame = view.bounds
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(label)
        }
    }

    #Preview("UIView") {
        ZooUIView()
    }

    #Preview("UIViewController") {
        ZooUIViewController()
    }
#endif

#if os(macOS)
    #Preview("macOS only") {
        Card(title: "macOS", subtitle: "Compiled only for macOS")
    }
#endif
