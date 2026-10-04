import Foundation

/// The process-wide time zone, which Foundation's date formatting reads.
///
/// Setting `NSTimeZone.default` isn't enough: format styles use the system time zone, which
/// only follows `TZ` after a reset.
enum ProcessTimeZone {
    static func set(_ identifier: String) -> String? {
        let previous = ProcessInfo.processInfo.environment["TZ"]
        setenv("TZ", identifier, 1)
        tzset()
        NSTimeZone.resetSystemTimeZone()
        return previous
    }

    static func restore(_ previous: String?) {
        if let previous { setenv("TZ", previous, 1) } else { unsetenv("TZ") }
        tzset()
        NSTimeZone.resetSystemTimeZone()
    }
}
