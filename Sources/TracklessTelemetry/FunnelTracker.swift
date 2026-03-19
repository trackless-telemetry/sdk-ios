import Foundation

/// In-memory funnel step deduplication per session.
///
/// Tracks which step indices have been recorded per funnel name within a session.
/// Prevents the same step from being counted twice in one session.
/// Cleared on session end.
actor FunnelTracker {

    /// Map of funnelName -> set of completed step indices.
    private var funnels: [String: Set<Int>] = [:]

    init() {}

    /// Check and record a funnel step for deduplication.
    ///
    /// - Returns: true if the step was newly recorded, false if it was a duplicate.
    func step(funnelName: String, stepIndex: Int) -> Bool {
        var steps = funnels[funnelName] ?? Set<Int>()

        // Dedup — if this step index was already recorded, skip
        if steps.contains(stepIndex) { return false }

        steps.insert(stepIndex)
        funnels[funnelName] = steps
        return true
    }

    /// Clear all funnel state (call on session end).
    func clear() {
        funnels.removeAll()
    }
}
