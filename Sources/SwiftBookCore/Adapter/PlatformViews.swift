import SwiftUI

/// Wraps the AppKit and UIKit views and view controllers that `#Preview` accepts.
@MainActor enum PlatformViews {
    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        static func wrap(_ view: NSView) -> AnyView { AnyView(HostedView(view: view)) }
        static func wrap(_ controller: NSViewController) -> AnyView {
            AnyView(HostedController(controller: controller))
        }
    #elseif canImport(UIKit)
        static func wrap(_ view: UIView) -> AnyView { AnyView(HostedView(view: view)) }
        static func wrap(_ controller: UIViewController) -> AnyView {
            AnyView(HostedController(controller: controller))
        }
    #endif
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
    private struct HostedView: NSViewRepresentable {
        let view: NSView
        func makeNSView(context: Context) -> NSView { view }
        func updateNSView(_ view: NSView, context: Context) {}

        /// The view's intrinsic size where it has one, as in Xcode's canvas.
        func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSView, context: Context)
            -> CGSize?
        {
            intrinsicSize(
                view.intrinsicContentSize, noMetric: NSView.noIntrinsicMetric, proposal: proposal)
        }
    }

    private struct HostedController: NSViewControllerRepresentable {
        let controller: NSViewController
        func makeNSViewController(context: Context) -> NSViewController { controller }
        func updateNSViewController(_ controller: NSViewController, context: Context) {}
    }
#elseif canImport(UIKit)
    private struct HostedView: UIViewRepresentable {
        let view: UIView
        func makeUIView(context: Context) -> UIView { view }
        func updateUIView(_ view: UIView, context: Context) {}

        /// The view's intrinsic size where it has one, as in Xcode's canvas.
        func sizeThatFits(_ proposal: ProposedViewSize, uiView view: UIView, context: Context)
            -> CGSize?
        {
            intrinsicSize(
                view.intrinsicContentSize, noMetric: UIView.noIntrinsicMetric, proposal: proposal)
        }
    }

    private struct HostedController: UIViewControllerRepresentable {
        let controller: UIViewController
        func makeUIViewController(context: Context) -> UIViewController { controller }
        func updateUIViewController(_ controller: UIViewController, context: Context) {}
    }
#endif

/// An intrinsic size, filling the proposal on any axis without an intrinsic metric.
private func intrinsicSize(_ intrinsic: CGSize, noMetric: CGFloat, proposal: ProposedViewSize)
    -> CGSize?
{
    guard intrinsic.width != noMetric || intrinsic.height != noMetric else { return nil }
    return CGSize(
        width: intrinsic.width != noMetric ? intrinsic.width : proposal.width ?? intrinsic.width,
        height: intrinsic.height != noMetric
            ? intrinsic.height : proposal.height ?? intrinsic.height)
}
