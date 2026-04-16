import Foundation

/// Event types supported by Trackless.
enum TracklessEventType: String, Codable, Sendable {
    case session
    case view
    case feature
    case funnel
    case performance
    case error
}

/// Error severity levels.
public enum TracklessErrorSeverity: String, Codable, Sendable {
    case debug
    case info
    case warning
    case error
    case fatal
}

/// Environment for the SDK payload.
public enum TracklessEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}

/// Coarse device context — no fingerprinting data.
///
/// Privacy invariants enforced:
/// - NO IDFA or IDFV (Invariant 1)
/// - NO device name or model string (Invariant 2)
/// - NO IP-based geolocation (Invariant 4)
/// - Region derived from system Locale only
struct TracklessEventContext: Codable, Sendable, Equatable {
    let platform: String
    let osVersion: String?
    let deviceClass: String?
    let region: String?
    let language: String?
    let appVersion: String?
    let buildNumber: String?
    let daysSinceInstall: Int?
    let sdkVersion: String?
    let distributionChannel: String?

    init(
        platform: String = "ios",
        osVersion: String? = nil,
        deviceClass: String? = nil,
        region: String? = nil,
        language: String? = nil,
        appVersion: String? = nil,
        buildNumber: String? = nil,
        daysSinceInstall: Int? = nil,
        sdkVersion: String? = nil,
        distributionChannel: String? = nil
    ) {
        self.platform = platform
        self.osVersion = osVersion
        self.deviceClass = deviceClass
        self.region = region
        self.language = language
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.daysSinceInstall = daysSinceInstall
        self.sdkVersion = sdkVersion
        self.distributionChannel = distributionChannel
    }
}

/// A single event in the payload.
struct TracklessEvent: Codable, Sendable, Equatable {
    let type: TracklessEventType
    let name: String
    var count: Int?
    var detail: String?
    var step: String?
    var stepIndex: Int?
    var duration: Double?
    var durations: [Double]?
    var threshold: Double?
    var severity: TracklessErrorSeverity?
    var code: String?

    init(
        type: TracklessEventType,
        name: String,
        count: Int? = nil,
        detail: String? = nil,
        step: String? = nil,
        stepIndex: Int? = nil,
        duration: Double? = nil,
        durations: [Double]? = nil,
        threshold: Double? = nil,
        severity: TracklessErrorSeverity? = nil,
        code: String? = nil
    ) {
        self.type = type
        self.name = name
        self.count = count
        self.detail = detail
        self.step = step
        self.stepIndex = stepIndex
        self.duration = duration
        self.durations = durations
        self.threshold = threshold
        self.severity = severity
        self.code = code
    }
}

/// Full event payload sent to the ingest endpoint.
struct TracklessEventPayload: Codable, Sendable, Equatable {
    let date: String
    let environment: String?
    let context: TracklessEventContext
    let events: [TracklessEvent]

    init(date: String, environment: String?, context: TracklessEventContext, events: [TracklessEvent]) {
        self.date = date
        self.environment = environment
        self.context = context
        self.events = events
    }
}

/// Response from the ingest endpoint.
struct TracklessIngestResponse: Codable, Sendable {
    let accepted: Int?
    let rejected: Int?
}
