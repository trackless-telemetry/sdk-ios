import Testing
import Foundation
@testable import TracklessTelemetry

// Coverage for Feature Reach (session-reach dedup) — spec §25.4 / §25.6.

// MARK: - First-Use Tracker

@Suite("Feature Reach — First-Use Tracker")
struct FeatureFirstUseTrackerTests {

    @Test("First use returns true, repeat in the same session returns false")
    func firstUseThenRepeat() async {
        let tracker = FeatureFirstUseTracker()
        #expect(await tracker.markFirstUse(name: "export") == true)
        #expect(await tracker.markFirstUse(name: "export") == false)
    }

    @Test("Distinct feature names dedup independently")
    func distinctNamesIndependent() async {
        let tracker = FeatureFirstUseTracker()
        #expect(await tracker.markFirstUse(name: "export") == true)
        #expect(await tracker.markFirstUse(name: "import") == true)
        // Both are now seen — repeats return false regardless of order.
        #expect(await tracker.markFirstUse(name: "export") == false)
        #expect(await tracker.markFirstUse(name: "import") == false)
    }

    @Test("clear() resets the set so a name counts as first-use again")
    func clearResets() async {
        let tracker = FeatureFirstUseTracker()
        #expect(await tracker.markFirstUse(name: "export") == true)
        #expect(await tracker.markFirstUse(name: "export") == false)
        await tracker.clear()
        #expect(await tracker.markFirstUse(name: "export") == true)
    }
}

// MARK: - Buffer firstUses Rollup

@Suite("Feature Reach — Buffer firstUses rollup")
struct FeatureReachBufferTests {

    private let testContext = TracklessEventContext(platform: "ios")

    @Test("addCountable sums firstUses across a first use and a repeat")
    func sumsFirstUseWithRepeat() async {
        let buffer = EventBuffer()
        await buffer.add(TracklessEvent(type: .feature, name: "export", firstUses: 1))
        await buffer.add(TracklessEvent(type: .feature, name: "export")) // repeat — firstUses nil

        let size = await buffer.totalSize
        #expect(size == 1)

        let payloads = await buffer.drain(environment: "production", context: testContext)
        let event = payloads[0].events[0]
        #expect(event.count == 2)
        #expect(event.firstUses == 1)
    }

    @Test("addCountable sums two firstUses across a session boundary")
    func sumsTwoFirstUses() async {
        // firstUses:1 in one session, then firstUses:1 again after a new session, both
        // landing in the same rollup key before the buffer drains (a flush was held off,
        // e.g. by the circuit breaker). Spec §25.4.2: a payload may legitimately carry
        // firstUses:2 with a larger count.
        let buffer = EventBuffer()
        await buffer.add(TracklessEvent(type: .feature, name: "export", count: 4, firstUses: 1))
        await buffer.add(TracklessEvent(type: .feature, name: "export", count: 3, firstUses: 1))

        let payloads = await buffer.drain(environment: "production", context: testContext)
        #expect(payloads[0].events[0].count == 7)
        #expect(payloads[0].events[0].firstUses == 2)
    }

    @Test("Repeat-only feature entry drains without firstUses (never 0)")
    func repeatOnlyNoFirstUses() async {
        let buffer = EventBuffer()
        await buffer.add(TracklessEvent(type: .feature, name: "export")) // no firstUses
        await buffer.add(TracklessEvent(type: .feature, name: "export"))

        let payloads = await buffer.drain(environment: "production", context: testContext)
        let event = payloads[0].events[0]
        #expect(event.count == 2)
        #expect(event.firstUses == nil)
    }

    @Test("Different-detail variant after a first use carries no firstUses")
    func differentDetailNoFirstUses() async {
        // Name-only dedup: the first feature("export") got firstUses:1 on the base
        // (detail-less) variant; a later export/csv is a separate rollup entry with no
        // first-use of its own.
        let buffer = EventBuffer()
        await buffer.add(TracklessEvent(type: .feature, name: "export", firstUses: 1)) // detail nil
        await buffer.add(TracklessEvent(type: .feature, name: "export", detail: "csv")) // firstUses nil

        let size = await buffer.totalSize
        #expect(size == 2)

        let payloads = await buffer.drain(environment: "production", context: testContext)
        let base = payloads[0].events.first(where: { $0.detail == nil })
        let csv = payloads[0].events.first(where: { $0.detail == "csv" })
        #expect(base?.firstUses == 1)
        #expect(csv?.firstUses == nil)
    }
}

// MARK: - Wire Encoding

@Suite("Feature Reach — Wire encoding")
struct FeatureReachEncodingTests {

    @Test("firstUses is omitted from JSON when nil")
    func omitsWhenNil() throws {
        let event = TracklessEvent(type: .feature, name: "export", count: 3)
        let data = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["count"] as? Int == 3)
        #expect(json.keys.contains("firstUses") == false)
    }

    @Test("firstUses is encoded when >= 1")
    func encodesWhenPresent() throws {
        let event = TracklessEvent(type: .feature, name: "export", count: 5, firstUses: 2)
        let data = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["firstUses"] as? Int == 2)
    }
}

// MARK: - recordEvent Integration

@Suite("Feature Reach — recordEvent integration")
struct FeatureReachIntegrationTests {

    /// A configured state with a long flush interval so the periodic timer never fires
    /// during the test. Tests must call `setEnabled(false)` at the end to cancel the
    /// timer cleanly.
    private func makeConfiguredState() async -> TracklessState {
        let state = TracklessState()
        let config = TracklessConfig(
            apiKey: "tl_test",
            endpoint: "https://example.invalid",
            environment: .sandbox,
            enabled: true,
            onError: nil,
            flushIntervalSeconds: 3600,
            debugLogging: false,
            suppressWarnings: true
        )
        await state.configure(config)
        return state
    }

    private func featureEvent(in events: [TracklessEvent], name: String) -> TracklessEvent? {
        events.first(where: { $0.type == .feature && $0.name == name })
    }

    @Test("First feature() carries firstUses:1; a repeat in the same session does not")
    func firstUseSetOnFeature() async {
        let state = await makeConfiguredState()

        await state.recordEvent(type: .feature, name: "export")
        var events = await state.drainBufferForTesting()
        #expect(featureEvent(in: events, name: "export")?.firstUses == 1)

        await state.recordEvent(type: .feature, name: "export")
        events = await state.drainBufferForTesting()
        #expect(featureEvent(in: events, name: "export")?.firstUses == nil)

        await state.setEnabled(false)
    }

    @Test("Dedup keys on the normalized name")
    func dedupUsesNormalizedName() async {
        let state = await makeConfiguredState()

        // "Export Flow" and "export_flow" normalize to the same name — the second is a
        // repeat, not a new first use.
        await state.recordEvent(type: .feature, name: "Export Flow")
        var events = await state.drainBufferForTesting()
        #expect(featureEvent(in: events, name: "export_flow")?.firstUses == 1)

        await state.recordEvent(type: .feature, name: "export_flow")
        events = await state.drainBufferForTesting()
        #expect(featureEvent(in: events, name: "export_flow")?.firstUses == nil)

        await state.setEnabled(false)
    }

    @Test("Distinct feature names each get their own first use")
    func distinctNamesEachFirstUse() async {
        let state = await makeConfiguredState()

        await state.recordEvent(type: .feature, name: "export")
        await state.recordEvent(type: .feature, name: "share")
        let events = await state.drainBufferForTesting()
        #expect(featureEvent(in: events, name: "export")?.firstUses == 1)
        #expect(featureEvent(in: events, name: "share")?.firstUses == 1)

        await state.setEnabled(false)
    }

    @Test("Non-feature events never carry firstUses")
    func viewEventsHaveNoFirstUses() async {
        let state = await makeConfiguredState()

        await state.recordEvent(type: .view, name: "home")
        await state.recordEvent(type: .view, name: "home")
        let events = await state.drainBufferForTesting()
        let view = events.first(where: { $0.type == .view && $0.name == "home" })
        #expect(view?.firstUses == nil)

        await state.setEnabled(false)
    }

    @Test("First-use set survives a mid-session flush but resets on session end")
    func setSurvivesFlushResetsOnSessionEnd() async {
        let state = await makeConfiguredState()

        // First use in the session.
        await state.recordEvent(type: .feature, name: "export")
        var events = await state.drainBufferForTesting() // simulates a mid-session flush drain
        #expect(featureEvent(in: events, name: "export")?.firstUses == 1)

        // Same session, after the flush: the set survived, so this is not a first use.
        await state.recordEvent(type: .feature, name: "export")
        events = await state.drainBufferForTesting()
        #expect(featureEvent(in: events, name: "export")?.firstUses == nil)

        // Session ends → the set clears. The next use is a first use again.
        await state.endSessionForTesting()
        await state.recordEvent(type: .feature, name: "export")
        events = await state.drainBufferForTesting()
        #expect(featureEvent(in: events, name: "export")?.firstUses == 1)

        await state.setEnabled(false)
    }
}
