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

    @Test("OS version is major version only")
    func osVersionExtracted() {
        let ctx = ContextDetection.detect()
        #expect(ctx.osVersion != nil)
        if let osVersion = ctx.osVersion {
            #expect(Int(osVersion) != nil)
            // Should match ProcessInfo major version
            let expectedMajor = String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
            #expect(osVersion == expectedMajor)
        }
    }

    // MARK: - Device Class

    @Test("Device class is a valid value or nil")
    func deviceClassValid() {
        let ctx = ContextDetection.detect()
        let validValues: Set<String?> = ["phone", "tablet", "desktop", nil]
        #expect(validValues.contains(ctx.deviceClass))
    }

    // MARK: - Region

    @Test("Region is non-empty country code or nil")
    func regionDetected() {
        let ctx = ContextDetection.detect()
        if let region = ctx.region {
            #expect(!region.isEmpty)
            // Country codes are 2 uppercase letters
            #expect(region.count == 2)
            #expect(region == region.uppercased())
        }
    }

    // MARK: - Language

    @Test("Language is non-empty lowercase code or nil")
    func languageDetected() {
        let ctx = ContextDetection.detect()
        if let language = ctx.language {
            #expect(!language.isEmpty)
            // Language codes are 2-3 lowercase letters (ISO 639-1)
            #expect(language.count >= 2 && language.count <= 3)
            #expect(language == language.lowercased())
        }
    }

    // MARK: - No Identifiers

    @Test("Context struct does not contain any identifiers")
    func noIdentifiers() {
        let ctx = ContextDetection.detect()
        #expect(ctx.platform == "ios")
        if let osVersion = ctx.osVersion {
            #expect(Int(osVersion) != nil)
        }
        if let dc = ctx.deviceClass {
            let allowed = ["phone", "tablet", "desktop"]
            #expect(allowed.contains(dc))
        }
    }

    // MARK: - SDK Version

    @Test("SDK version is present and starts with ios/")
    func sdkVersionPresent() {
        let ctx = ContextDetection.detect()
        #expect(ctx.sdkVersion != nil)
        if let sdkVersion = ctx.sdkVersion {
            #expect(sdkVersion.hasPrefix("ios/"))
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
