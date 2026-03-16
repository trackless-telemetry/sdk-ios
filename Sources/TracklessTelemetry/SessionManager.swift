import Foundation

/// In-memory session state manager.
///
/// Tracks session start time, depth (number of non-session events),
/// and inactivity timeout for new session detection.
///
/// Zero persistence — all state is in-memory only.
public actor SessionManager {

    /// Session inactivity timeout: 30 minutes.
    static let inactivityTimeoutSeconds: TimeInterval = 30 * 60

    private var startTime: Date?
    private var depth: Int = 0
    private var lastActivityTime: Date?
    private var active: Bool = false

    public init() {}

    /// Start a new session. Returns true if a new session was started.
    public func start() -> Bool {
        if active && !isExpired() { return false }

        startTime = Date()
        depth = 0
        lastActivityTime = Date()
        active = true
        return true
    }

    /// Record activity (non-session event). Increments depth.
    public func recordActivity() {
        guard active else { return }
        depth += 1
        lastActivityTime = Date()
    }

    /// End the current session. Returns duration in seconds and depth, or nil.
    public func end() -> (duration: Int, depth: Int)? {
        guard active, let start = startTime else { return nil }

        active = false
        let durationMs = Date().timeIntervalSince(start)
        let duration = Int(durationMs.rounded())
        return (duration: duration, depth: depth)
    }

    /// Check if session has expired due to inactivity.
    public func isExpired() -> Bool {
        guard active, let lastActivity = lastActivityTime else { return true }
        return Date().timeIntervalSince(lastActivity) >= Self.inactivityTimeoutSeconds
    }

    /// Whether a session is currently active.
    public var isActive: Bool {
        active && !isExpiredSync()
    }

    /// Current session depth.
    public var currentDepth: Int {
        depth
    }

    /// Clean up.
    public func destroy() {
        active = false
    }

    // Internal sync check for isActive property
    private func isExpiredSync() -> Bool {
        guard let lastActivity = lastActivityTime else { return true }
        return Date().timeIntervalSince(lastActivity) >= Self.inactivityTimeoutSeconds
    }
}
