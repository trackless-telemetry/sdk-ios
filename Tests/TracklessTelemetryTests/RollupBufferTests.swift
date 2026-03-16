import Testing
@testable import TracklessTelemetry

@Suite("EventBuffer Tests")
struct EventBufferTests {

    private let testContext = EventContext(
        platform: "ios",
        osVersion: "17.0",
        deviceClass: "phone",
        locale: "en-US"
    )

    // MARK: - Single Event

    @Test("Single feature event creates one buffer entry with count 1")
    func singleEvent() async {
        let buffer = EventBuffer()
        let added = await buffer.add(TracklessEvent(type: .feature, name: "export_clicked"))
        #expect(added == true)
        let size = await buffer.totalSize
        #expect(size == 1)
    }

    // MARK: - Multiple Same Events

    @Test("Multiple same feature events increment count, not size")
    func multipleSameEvents() async {
        let buffer = EventBuffer()
        for _ in 0..<5 {
            await buffer.add(TracklessEvent(type: .feature, name: "export_clicked"))
        }
        let size = await buffer.totalSize
        #expect(size == 1)

        let payloads = await buffer.drain(environment: "production", context: testContext)
        #expect(payloads.count == 1)
        #expect(payloads[0].events.count == 1)
        #expect(payloads[0].events[0].count == 5)
    }

    // MARK: - Empty Buffer

    @Test("Empty buffer drains to empty payloads")
    func emptyBuffer() async {
        let buffer = EventBuffer()
        let isEmpty = await buffer.isEmpty
        #expect(isEmpty == true)

        let payloads = await buffer.drain(environment: "production", context: testContext)
        #expect(payloads.isEmpty)
    }

    // MARK: - Bounded Memory

    @Test("Buffer respects max items limit")
    func boundedMemory() async {
        let buffer = EventBuffer(maxItems: 5)

        for i in 0..<5 {
            let added = await buffer.add(TracklessEvent(type: .feature, name: "feature_\(i)"))
            #expect(added == true)
        }

        let size = await buffer.totalSize
        #expect(size == 5)

        let dropped = await buffer.add(TracklessEvent(type: .feature, name: "feature_overflow"))
        #expect(dropped == false)

        // Existing features still increment
        let existing = await buffer.add(TracklessEvent(type: .feature, name: "feature_0"))
        #expect(existing == true)
    }

    // MARK: - Performance Events

    @Test("Performance events aggregate durations")
    func performanceDurations() async {
        let buffer = EventBuffer()
        await buffer.add(TracklessEvent(type: .performance, name: "api_call", duration: 100))
        await buffer.add(TracklessEvent(type: .performance, name: "api_call", duration: 200))
        await buffer.add(TracklessEvent(type: .performance, name: "api_call", duration: 150))

        let size = await buffer.totalSize
        #expect(size == 1)

        let payloads = await buffer.drain(environment: "production", context: testContext)
        #expect(payloads[0].events[0].durations == [100, 200, 150])
    }

    // MARK: - Funnel Events

    @Test("Funnel events are stored individually")
    func funnelEventsIndividual() async {
        let buffer = EventBuffer()
        await buffer.add(TracklessEvent(type: .funnel, name: "checkout", step: "cart", stepIndex: 0))
        await buffer.add(TracklessEvent(type: .funnel, name: "checkout", step: "payment", stepIndex: 1))

        let size = await buffer.totalSize
        #expect(size == 2)

        let payloads = await buffer.drain(environment: "production", context: testContext)
        #expect(payloads[0].events.count == 2)
    }

    // MARK: - Drain Produces Correct Payload

    @Test("Drain produces correct EventPayload with context")
    func drainPayload() async {
        let buffer = EventBuffer()
        await buffer.add(TracklessEvent(type: .feature, name: "settings_opened"))
        await buffer.add(TracklessEvent(type: .feature, name: "settings_opened"))
        await buffer.add(TracklessEvent(type: .screen, name: "home"))

        let payloads = await buffer.drain(environment: "sandbox", context: testContext)
        #expect(payloads.count == 1)
        #expect(payloads[0].events.count == 2)
        #expect(payloads[0].environment == "sandbox")
        #expect(payloads[0].context.platform == "ios")

        let settingsEvent = payloads[0].events.first { $0.name == "settings_opened" }
        #expect(settingsEvent?.count == 2)

        let isEmpty = await buffer.isEmpty
        #expect(isEmpty == true)
    }

    // MARK: - Clear

    @Test("Clear discards all buffered data")
    func clearDiscards() async {
        let buffer = EventBuffer()
        await buffer.add(TracklessEvent(type: .feature, name: "test"))
        let sizeBefore = await buffer.totalSize
        #expect(sizeBefore == 1)

        await buffer.clear()
        let sizeAfter = await buffer.totalSize
        #expect(sizeAfter == 0)
    }

    // MARK: - Thread Safety

    @Test("Thread safety under concurrent access")
    func threadSafety() async {
        let buffer = EventBuffer()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    await buffer.add(TracklessEvent(type: .feature, name: "concurrent_\(i % 10)"))
                }
            }
        }
        let size = await buffer.totalSize
        #expect(size == 10)

        let payloads = await buffer.drain(environment: "production", context: EventContext(platform: "ios"))
        let totalCount = payloads[0].events.reduce(0) { $0 + ($1.count ?? 1) }
        #expect(totalCount == 100)
    }

    // MARK: - Date Format

    @Test("Date field is in YYYY-MM-DD format")
    func dateFormat() async {
        let buffer = EventBuffer()
        await buffer.add(TracklessEvent(type: .feature, name: "test"))
        let payloads = await buffer.drain(environment: "production", context: testContext)
        let date = payloads[0].date
        let dateRegex = /^\d{4}-\d{2}-\d{2}$/
        #expect(date.contains(dateRegex))
    }

    // MARK: - Different Types Separate

    @Test("Different event types create separate entries")
    func differentTypesSeparate() async {
        let buffer = EventBuffer()
        await buffer.add(TracklessEvent(type: .feature, name: "export"))
        await buffer.add(TracklessEvent(type: .screen, name: "export"))

        let size = await buffer.totalSize
        #expect(size == 2)
    }
}
