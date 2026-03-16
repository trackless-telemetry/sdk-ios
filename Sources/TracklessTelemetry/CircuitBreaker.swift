import Foundation

/// Circuit breaker with exponential backoff for flush failures.
///
/// Only 5xx and network errors trigger backoff.
/// 4xx errors discard the batch but do NOT trigger the circuit breaker.
/// A single successful flush resets the failure count and backoff to zero.
///
/// Backoff delays: 30s, 1m, 5m, 15m, 60m (max)
public actor CircuitBreaker {

    /// Backoff delay schedule in seconds.
    static let delays: [TimeInterval] = [30, 60, 300, 900, 3600]

    private var consecutiveFailures: Int = 0
    private var nextRetryAt: Date = .distantPast

    public init() {}

    /// Can we attempt a flush right now?
    public func canAttempt() -> Bool {
        if consecutiveFailures == 0 { return true }
        return Date() >= nextRetryAt
    }

    /// Record a successful flush -- resets backoff entirely.
    public func recordSuccess() {
        consecutiveFailures = 0
        nextRetryAt = .distantPast
    }

    /// Record a flush failure -- advances backoff schedule.
    public func recordFailure() {
        consecutiveFailures += 1
        let delayIndex = min(consecutiveFailures - 1, Self.delays.count - 1)
        nextRetryAt = Date().addingTimeInterval(Self.delays[delayIndex])
    }

    /// Current consecutive failure count (for testing).
    public var failures: Int {
        consecutiveFailures
    }
}
