import Foundation

/// In-memory session state manager.
///
/// Tracks session start time and depth (number of non-session events).
///
/// Zero persistence — all state is in-memory only.
actor SessionManager {

    private var startTime: Date?
    private var depth: Int = 0
    private var active: Bool = false

    init() {}

    /// Start a new session. Returns true if a new session was started.
    func start() -> Bool {
        if active { return false }

        startTime = Date()
        depth = 0
        active = true
        return true
    }

    /// Record activity (non-session event). Increments depth.
    func recordActivity() {
        guard active else { return }
        depth += 1
    }

    /// End the current session. Returns duration in seconds and depth, or nil.
    func end() -> (duration: Int, depth: Int)? {
        guard active, let start = startTime else { return nil }

        active = false
        let durationMs = Date().timeIntervalSince(start)
        let duration = Int(durationMs.rounded())
        return (duration: duration, depth: depth)
    }

    /// Whether a session is currently active.
    var isActive: Bool {
        active
    }

    /// Current session depth.
    var currentDepth: Int {
        depth
    }

    /// Clean up.
    func destroy() {
        active = false
    }
}
