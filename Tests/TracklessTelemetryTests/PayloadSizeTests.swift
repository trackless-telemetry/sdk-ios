import Foundation
import Testing
@testable import TracklessTelemetry

@Suite("Payload Size Limit Tests")
struct PayloadSizeTests {

    private let testContext = TracklessEventContext(platform: "ios")

    private func makePayload(events: [TracklessEvent]) -> TracklessEventPayload {
        TracklessEventPayload(
            date: "2026-06-10",
            environment: "production",
            context: testContext,
            events: events
        )
    }

    private func encodedSize(_ payload: TracklessEventPayload) throws -> Int {
        try JSONEncoder().encode(payload).count
    }

    /// A single event whose encoded form exceeds the 50KB body limit on its own.
    private var oversizedEvent: TracklessEvent {
        TracklessEvent(
            type: .performance,
            name: "giant_trace",
            durations: Array(repeating: 123.456789, count: 8000)
        )
    }

    @Test("Limit matches the server's 50KB request body limit")
    func limitMatchesServer() {
        #expect(EventBuffer.maxPayloadBytes == 50 * 1024)
    }

    @Test("Payload under the limit passes through unchanged")
    func underLimitPassesThrough() {
        let payload = makePayload(events: [
            TracklessEvent(type: .feature, name: "export_clicked", count: 3),
            TracklessEvent(type: .view, name: "home", count: 1),
        ])

        let result = EventBuffer.splitBySize(payload)
        #expect(result.payloads == [payload])
        #expect(result.dropped.isEmpty)
    }

    @Test("Oversized payload splits recursively into size-compliant payloads preserving event order")
    func oversizedPayloadSplits() throws {
        let events = (0..<40).map {
            TracklessEvent(type: .feature, name: "feature_\(String(format: "%02d", $0))", count: 1)
        }
        let payload = makePayload(events: events)
        let limit = 600
        let originalSize = try encodedSize(payload)
        #expect(originalSize > limit)

        let result = EventBuffer.splitBySize(payload, limit: limit)
        #expect(result.dropped.isEmpty)
        #expect(result.payloads.count > 1)

        for sized in result.payloads {
            let size = try encodedSize(sized)
            #expect(size <= limit)
            // Wire format unchanged — same envelope on every split payload.
            #expect(sized.date == payload.date)
            #expect(sized.environment == payload.environment)
            #expect(sized.context == payload.context)
        }

        let flattened = result.payloads.flatMap { $0.events }
        #expect(flattened == events)
    }

    @Test("Single event exceeding the limit is dropped")
    func oversizedSingleEventDropped() throws {
        let huge = oversizedEvent
        let payload = makePayload(events: [huge])
        let size = try encodedSize(payload)
        #expect(size > EventBuffer.maxPayloadBytes)

        let result = EventBuffer.splitBySize(payload)
        #expect(result.payloads.isEmpty)
        #expect(result.dropped == [huge])
    }

    @Test("Oversized single event is dropped while surrounding events are kept")
    func mixedOversizedEventDropped() throws {
        let small1 = TracklessEvent(type: .feature, name: "small_one", count: 5)
        let huge = oversizedEvent
        let small2 = TracklessEvent(type: .view, name: "small_two", count: 2)
        let payload = makePayload(events: [small1, huge, small2])

        let result = EventBuffer.splitBySize(payload)
        #expect(result.dropped == [huge])

        let kept = result.payloads.flatMap { $0.events }
        #expect(kept == [small1, small2])

        for sized in result.payloads {
            let size = try encodedSize(sized)
            #expect(size <= EventBuffer.maxPayloadBytes)
        }
    }
}
