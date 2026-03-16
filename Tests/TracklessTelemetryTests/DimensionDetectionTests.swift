import Testing
import Foundation
@testable import TracklessTelemetry

@Suite("ContextDetection Tests")
struct ContextDetectionTests {

    // MARK: - Platform

    @Test("Platform is always ios")
    func platformIsIos() {
        let ctx = ContextDetection.detect()
        #expect(ctx.platform == "ios")
    }

    // MARK: - OS Version

    @Test("OS version is major.minor format")
    func osVersionExtracted() {
        let ctx = ContextDetection.detect()
        #expect(ctx.osVersion != nil)
        if let osVersion = ctx.osVersion {
            let parts = osVersion.split(separator: ".")
            #expect(parts.count == 2)
            #expect(Int(parts[0]) != nil)
            #expect(Int(parts[1]) != nil)
            // Major should match ProcessInfo
            let expectedMajor = String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
            #expect(String(parts[0]) == expectedMajor)
        }
    }

    // MARK: - Device Class

    @Test("Device class is a valid value or nil")
    func deviceClassValid() {
        let ctx = ContextDetection.detect()
        let validValues: Set<String?> = ["phone", "tablet", "desktop", nil]
        #expect(validValues.contains(ctx.deviceClass))
    }

    // MARK: - Locale

    @Test("Locale is non-empty string or nil")
    func localeDetected() {
        let ctx = ContextDetection.detect()
        if let locale = ctx.locale {
            #expect(!locale.isEmpty)
        }
    }

    // MARK: - No Identifiers

    @Test("Context struct does not contain any identifiers")
    func noIdentifiers() {
        let ctx = ContextDetection.detect()
        #expect(ctx.platform == "ios")
        if let osVersion = ctx.osVersion {
            #expect(osVersion.contains("."))
        }
        if let dc = ctx.deviceClass {
            let allowed = ["phone", "tablet", "desktop"]
            #expect(allowed.contains(dc))
        }
    }

    // MARK: - Environment Auto-Detection

    @Test("Environment auto-detection returns sandbox in DEBUG builds")
    func environmentAutoDetection() {
        let env = Trackless.detectEnvironment()
        #if DEBUG
        #expect(env == .sandbox)
        #else
        #expect(env == .production)
        #endif
    }
}
