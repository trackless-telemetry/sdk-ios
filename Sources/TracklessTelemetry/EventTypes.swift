import Foundation

/// Event types supported by Trackless.
public enum TracklessEventType: String, Codable, Sendable {
    case session
    case screen
    case feature
    case funnel
    case selection
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
public struct TracklessEventContext: Codable, Sendable, Equatable {
    public let platform: String
    public let osVersion: String?
    public let deviceClass: String?
    public let region: String?
    public let appVersion: String?
    public let buildNumber: String?
    public let daysSinceInstall: Int?

    public init(
        platform: String = "ios",
        osVersion: String? = nil,
        deviceClass: String? = nil,
        region: String? = nil,
        appVersion: String? = nil,
        buildNumber: String? = nil,
        daysSinceInstall: Int? = nil
    ) {
        self.platform = platform
        self.osVersion = osVersion
        self.deviceClass = deviceClass
        self.region = region
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.daysSinceInstall = daysSinceInstall
    }
}

/// A single event in the payload.
public struct TracklessEvent: Codable, Sendable, Equatable {
    public let type: TracklessEventType
    public let name: String
    public var count: Int?
    public var option: String?
    public var step: String?
    public var stepIndex: Int?
    public var duration: Double?
    public var durations: [Double]?
    public var severity: TracklessErrorSeverity?
    public var code: String?

    public init(
        type: TracklessEventType,
        name: String,
        count: Int? = nil,
        option: String? = nil,
        step: String? = nil,
        stepIndex: Int? = nil,
        duration: Double? = nil,
        durations: [Double]? = nil,
        severity: TracklessErrorSeverity? = nil,
        code: String? = nil
    ) {
        self.type = type
        self.name = name
        self.count = count
        self.option = option
        self.step = step
        self.stepIndex = stepIndex
        self.duration = duration
        self.durations = durations
        self.severity = severity
        self.code = code
    }
}

/// Full event payload sent to the ingest endpoint.
public struct TracklessEventPayload: Codable, Sendable, Equatable {
    public let date: String
    public let environment: String?
    public let context: TracklessEventContext
    public let events: [TracklessEvent]

    public init(date: String, environment: String?, context: TracklessEventContext, events: [TracklessEvent]) {
        self.date = date
        self.environment = environment
        self.context = context
        self.events = events
    }
}

/// Response from the ingest endpoint.
public struct TracklessIngestResponse: Codable, Sendable {
    public let accepted: Int?
    public let rejected: Int?
}
