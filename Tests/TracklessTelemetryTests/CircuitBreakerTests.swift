import Testing
import Foundation
@testable import TracklessTelemetry

@Suite("CircuitBreaker Tests")
struct CircuitBreakerTests {

    // MARK: - Initial state

    @Test("Initial state allows attempts")
    func initialStateAllowsAttempts() async {
        let cb = CircuitBreaker()
        let canAttempt = await cb.canAttempt()
        #expect(canAttempt == true)
        let failures = await cb.failures
        #expect(failures == 0)
    }

    // MARK: - Test 10: Circuit breaker backoff on 5xx

    @Test("Single failure blocks immediate retry")
    func singleFailureBlocks() async {
        let cb = CircuitBreaker()
        await cb.recordFailure()

        let failures = await cb.failures
        #expect(failures == 1)

        // Should not allow immediate retry (30s backoff)
        let canAttempt = await cb.canAttempt()
        #expect(canAttempt == false)
    }

    @Test("Consecutive failures increment failure count")
    func consecutiveFailures() async {
        let cb = CircuitBreaker()
        await cb.recordFailure()
        await cb.recordFailure()
        await cb.recordFailure()

        let failures = await cb.failures
        #expect(failures == 3)
    }

    @Test("Success resets failure count and allows attempts")
    func successResetsBackoff() async {
        let cb = CircuitBreaker()
        await cb.recordFailure()
        await cb.recordFailure()

        await cb.recordSuccess()

        let failures = await cb.failures
        #expect(failures == 0)

        let canAttempt = await cb.canAttempt()
        #expect(canAttempt == true)
    }

    // MARK: - Backoff schedule

    @Test("Backoff delays follow the defined schedule")
    func backoffSchedule() {
        // Verify the delay constants
        #expect(CircuitBreaker.delays.count == 5)
        #expect(CircuitBreaker.delays[0] == 30)     // 30 seconds
        #expect(CircuitBreaker.delays[1] == 60)     // 1 minute
        #expect(CircuitBreaker.delays[2] == 300)    // 5 minutes
        #expect(CircuitBreaker.delays[3] == 900)    // 15 minutes
        #expect(CircuitBreaker.delays[4] == 3600)   // 60 minutes (max)
    }

    @Test("Max failures cap at last delay")
    func maxFailuresCap() async {
        let cb = CircuitBreaker()
        // Record more failures than delay entries
        for _ in 0..<10 {
            await cb.recordFailure()
        }

        let failures = await cb.failures
        #expect(failures == 10)

        // Should still be blocked (using max delay of 60 minutes)
        let canAttempt = await cb.canAttempt()
        #expect(canAttempt == false)
    }
}
