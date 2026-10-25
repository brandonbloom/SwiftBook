/// The class of device a story renders on. Its platform follows from it.
package enum Device: String, Hashable, Sendable, CaseIterable {
    case mac
    case catalyst
    case iphone
    case ipad
    case tv
}
