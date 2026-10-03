#if os(macOS)
    import CoreGraphics
    @testable import SwiftBookCore
    import Testing

    @Suite struct CaptureMethodTests {
        @Test func followsTheEnvironmentVariable() throws {
            #expect(try CaptureMethod.current(["SWIFTBOOK_CAPTURE": "emulated"]) == .emulated)
            #expect(
                try CaptureMethod.current(["SWIFTBOOK_CAPTURE": "windowServer"]) == .windowServer)
            #expect(throws: (any Error).self) {
                try CaptureMethod.current(["SWIFTBOOK_CAPTURE": "gpu"])
            }
        }

        @Test func defaultsToTheWindowServerWhenPermitted() throws {
            let permitted = CGPreflightScreenCaptureAccess() && !CaptureMethod.screenIsLocked
            let expected: CaptureMethod = permitted ? .windowServer : .emulated
            #expect(try CaptureMethod.current([:]) == expected)
        }
    }
#endif
