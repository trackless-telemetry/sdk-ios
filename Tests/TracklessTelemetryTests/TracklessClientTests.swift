import Testing
import Foundation
@testable import TracklessTelemetry

@Suite("Trackless Static API Tests")
struct TracklessClientTests {

    // MARK: - EventBuffer Unit Tests (used by the static API)

    @Test("EventBuffer: feature events aggregate count")
    func featureEventsAggregate() async {
        let buffer = EventBuffer()
        await buffer.add(TracklessEvent(type: .feature, name: "export_clicked"))
        await buffer.add(TracklessEvent(type: .feature, name: "export_clicked"))
        await buffer.add(TracklessEvent(type: .feature, name: "export_clicked"))

        let payloads = await buffer.drain(
            environment: "production",
            context: EventContext(platform: "ios")
        )
        #expect(payloads[0].events[0].count == 3)
    }

    @Test("EventBuffer: screen events aggregate count")
    func screenEventsAggregate() async {
        let buffer = EventBuffer()
        await buffer.add(TracklessEvent(type: .screen, name: "home"))
        await buffer.add(TracklessEvent(type: .screen, name: "home"))

        let payloads = await buffer.drain(
            environment: "production",
            context: EventContext(platform: "ios")
        )
        #expect(payloads[0].events[0].count == 2)
    }

    @Test("EventBuffer: error events aggregate by severity+code")
    func errorEventsAggregate() async {
        let buffer = EventBuffer()
        await buffer.add(TracklessEvent(type: .error, name: "crash", severity: .fatal, code: "E001"))
        await buffer.add(TracklessEvent(type: .error, name: "crash", severity: .fatal, code: "E001"))
        // Different code = different entry
        await buffer.add(TracklessEvent(type: .error, name: "crash", severity: .fatal, code: "E002"))

        let size = await buffer.totalSize
        #expect(size == 2)
    }

    @Test("EventBuffer: selection events aggregate by option")
    func selectionEventsAggregate() async {
        let buffer = EventBuffer()
        await buffer.add(TracklessEvent(type: .selection, name: "theme", option: "dark"))
        await buffer.add(TracklessEvent(type: .selection, name: "theme", option: "dark"))
        await buffer.add(TracklessEvent(type: .selection, name: "theme", option: "light"))

        let size = await buffer.totalSize
        #expect(size == 2)
    }

    // MARK: - Session Manager

    @Test("SessionManager tracks duration and depth")
    func sessionDurationAndDepth() async {
        let session = SessionManager()
        let started = await session.start()
        #expect(started == true)

        await session.recordActivity()
        await session.recordActivity()
        await session.recordActivity()

        let result = await session.end()
        #expect(result != nil)
        #expect(result?.depth == 3)
        #expect((result?.duration ?? -1) >= 0)
    }

    @Test("SessionManager start returns false if already active")
    func sessionStartIdempotent() async {
        let session = SessionManager()
        let first = await session.start()
        #expect(first == true)
        let second = await session.start()
        #expect(second == false)
    }

    @Test("SessionManager end returns nil if no active session")
    func sessionEndNoSession() async {
        let session = SessionManager()
        let result = await session.end()
        #expect(result == nil)
    }

    // MARK: - Funnel Tracker

    @Test("FunnelTracker assigns sequential stepIndex")
    func funnelSequentialIndex() async {
        let tracker = FunnelTracker()
        let step0 = await tracker.step(funnelName: "checkout", stepName: "cart")
        let step1 = await tracker.step(funnelName: "checkout", stepName: "payment")
        let step2 = await tracker.step(funnelName: "checkout", stepName: "confirm")
        #expect(step0 == 0)
        #expect(step1 == 1)
        #expect(step2 == 2)
    }

    @Test("FunnelTracker deduplicates repeated steps")
    func funnelDedup() async {
        let tracker = FunnelTracker()
        let first = await tracker.step(funnelName: "checkout", stepName: "cart")
        let second = await tracker.step(funnelName: "checkout", stepName: "cart")
        #expect(first == 0)
        #expect(second == nil)
    }

    @Test("FunnelTracker tracks independent funnels")
    func funnelIndependent() async {
        let tracker = FunnelTracker()
        let a0 = await tracker.step(funnelName: "checkout", stepName: "cart")
        let b0 = await tracker.step(funnelName: "onboarding", stepName: "welcome")
        let a1 = await tracker.step(funnelName: "checkout", stepName: "payment")
        #expect(a0 == 0)
        #expect(b0 == 0)
        #expect(a1 == 1)
    }

    // MARK: - PII Guard

    @Test("PIIGuard strips blocked keys")
    func piiBlockedKeys() {
        let result = PIIGuard.sanitize(["email": "test@test.com", "category": "electronics"])
        #expect(result == ["category": "electronics"])
    }

    @Test("PIIGuard strips values matching PII patterns")
    func piiValuePatterns() {
        let result = PIIGuard.sanitize(["contact": "user@example.com", "color": "blue"])
        #expect(result == ["color": "blue"])
    }

    @Test("PIIGuard enforces max 10 properties")
    func piiMaxProperties() {
        var props: [String: String] = [:]
        for i in 0..<15 {
            props["key_\(i)"] = "value_\(i)"
        }
        let result = PIIGuard.sanitize(props)
        #expect(result != nil)
        #expect(result!.count == 10)
    }

    @Test("PIIGuard returns nil when all properties stripped")
    func piiAllStripped() {
        let result = PIIGuard.sanitize(["email": "test@test.com", "phone": "555-123-4567"])
        #expect(result == nil)
    }

    // MARK: - Event Payload Structure

    @Test("EventPayload encodes to correct JSON structure")
    func payloadEncoding() throws {
        let payload = EventPayload(
            date: "2026-03-14",
            environment: "sandbox",
            context: EventContext(platform: "ios", osVersion: "17.0"),
            events: [
                TracklessEvent(type: .feature, name: "export_clicked", count: 3),
                TracklessEvent(type: .screen, name: "home", count: 1),
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["date"] as? String == "2026-03-14")
        #expect(json["environment"] as? String == "sandbox")

        let context = json["context"] as? [String: Any]
        #expect(context?["platform"] as? String == "ios")

        let events = json["events"] as? [[String: Any]]
        #expect(events?.count == 2)
    }

    // MARK: - Environment

    @Test("Environment auto-detection returns sandbox in DEBUG builds")
    func environmentDetection() {
        let env = Trackless.detectEnvironment()
        #if DEBUG
        #expect(env == .sandbox)
        #else
        #expect(env == .production)
        #endif
    }

    // MARK: - TracklessError Cases

    @Test("TracklessError.flushRejected carries status code and body")
    func flushRejectedErrorCase() {
        let error = TracklessError.flushRejected(statusCode: 429, body: "Rate limited")
        if case .flushRejected(let code, let body) = error {
            #expect(code == 429)
            #expect(body == "Rate limited")
        } else {
            Issue.record("Expected flushRejected case")
        }
    }

    @Test("TracklessError.flushFailed carries status code")
    func flushFailedErrorCase() {
        let error = TracklessError.flushFailed(statusCode: 503)
        if case .flushFailed(let code) = error {
            #expect(code == 503)
        } else {
            Issue.record("Expected flushFailed case")
        }
    }

    // MARK: - Feature Validator (unchanged, verify still works with new types)

    @Test("Valid event names pass validation")
    func validNames() {
        #expect(FeatureValidator.isValid("export_clicked") == true)
        #expect(FeatureValidator.isValid("theme.dark") == true)
        #expect(FeatureValidator.isValid("a") == true)
    }

    @Test("Invalid event names fail validation")
    func invalidNames() {
        #expect(FeatureValidator.isValid("") == false)
        #expect(FeatureValidator.isValid("has space") == false)
        #expect(FeatureValidator.isValid(".starts_with_dot") == false)
        #expect(FeatureValidator.isValid(String(repeating: "a", count: 101)) == false)
    }
}

// MARK: - Test Helpers

/// Thread-safe error collector for async tests.
final class ErrorHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _errors: [Error] = []

    var errors: [Error] {
        lock.lock()
        defer { lock.unlock() }
        return _errors
    }

    func record(_ error: Error) {
        lock.lock()
        _errors.append(error)
        lock.unlock()
    }
}
