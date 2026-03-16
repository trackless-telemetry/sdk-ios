import Foundation

/// In-memory funnel step tracking per session.
///
/// Tracks which steps have been completed per funnel name within a session.
/// Provides deduplication and automatic stepIndex assignment.
/// Cleared on session end.
public actor FunnelTracker {

    /// Map of funnelName -> list of completed step names (in order).
    private var funnels: [String: [String]] = [:]

    public init() {}

    /// Record a funnel step.
    ///
    /// - Returns: stepIndex if the step was recorded, or nil if it was a duplicate.
    public func step(funnelName: String, stepName: String) -> Int? {
        var steps = funnels[funnelName] ?? []

        // Dedup — if this step was already completed, skip
        if steps.contains(stepName) { return nil }

        let stepIndex = steps.count
        steps.append(stepName)
        funnels[funnelName] = steps
        return stepIndex
    }

    /// Clear all funnel state (call on session end).
    public func clear() {
        funnels.removeAll()
    }
}
