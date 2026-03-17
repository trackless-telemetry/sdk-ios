import Foundation
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

/// Detects coarse device context from system APIs.
///
/// Privacy invariants enforced:
/// - NO IDFA collection (no AdSupport framework)
/// - NO IDFV collection (no UIDevice.identifierForVendor)
/// - NO device name or model string (Invariant 2)
/// - NO carrier info or telephony data
/// - NO IP-based geolocation (Invariant 4)
/// - Region from system Locale only, never from network info
enum ContextDetection {

    /// Detect coarse device context. Captured once at configure time.
    static func detect() -> TracklessEventContext {
        TracklessEventContext(
            platform: "ios",
            osVersion: detectOsVersion(),
            deviceClass: detectDeviceClass(),
            region: detectRegion(),
            appVersion: detectAppVersion(),
            buildNumber: detectBuildNumber(),
            daysSinceInstall: detectDaysSinceInstall()
        )
    }

    // MARK: - Private

    /// Extract major OS version only.
    private static func detectOsVersion() -> String? {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion)"
    }

    /// Detect device class from UIDevice.current.userInterfaceIdiom.
    private static func detectDeviceClass() -> String? {
        #if os(iOS) || os(tvOS) || os(visionOS)
        let idiom = UIDevice.current.userInterfaceIdiom
        switch idiom {
        case .phone:
            return "phone"
        case .pad:
            return "tablet"
        case .mac:
            return "desktop"
        case .tv:
            return "desktop"
        case .carPlay:
            return nil
        case .unspecified:
            return nil
        @unknown default:
            return nil
        }
        #elseif os(macOS)
        return "desktop"
        #else
        return nil
        #endif
    }

    /// Extract country code from system Locale (e.g., "US").
    /// Derived from system setting, NOT from IP address.
    private static func detectRegion() -> String? {
        if #available(iOS 16, macOS 13, *) {
            return Locale.current.region?.identifier
        } else {
            // iOS 15 / macOS 12 fallback
            return Locale.current.regionCode
        }
    }

    /// App version from Bundle.main (e.g., "1.2.3").
    private static func detectAppVersion() -> String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Build number from Bundle.main (e.g., "42").
    private static func detectBuildNumber() -> String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    /// Days since first install, derived from the Documents directory creation date.
    /// Read-only filesystem query — no disk writes.
    private static func detectDaysSinceInstall() -> Int? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: documentsURL.path),
              let creationDate = attributes[.creationDate] as? Date else {
            return nil
        }
        let days = Calendar.current.dateComponents([.day], from: creationDate, to: Date()).day
        return days
    }
}
