import Foundation

/// Thread-safe in-memory event buffer with client-side rollup.
///
/// Count-aggregatable events (feature, screen, error, selection, event)
/// are rolled up by key. Performance events append to durations[].
/// Non-aggregatable events (funnel, session start/end) are appended individually.
///
/// Uses Swift actor for thread safety (Swift 6 strict concurrency).
public actor EventBuffer {

    /// Default max unique items in the buffer.
    public static let defaultMaxItems = 1000

    /// Max events per flush payload.
    static let maxEventsPerFlush = 100

    /// Aggregated events keyed by rollup key.
    private var aggregated: [String: TracklessEvent] = [:]
    /// Non-aggregatable events (funnel steps, session start/end).
    private var individual: [TracklessEvent] = []
    private let maxItems: Int

    /// Local-time date formatter for date bucketing.
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    public init(maxItems: Int = EventBuffer.defaultMaxItems) {
        self.maxItems = maxItems
    }

    /// Add an event to the buffer. Returns true if accepted.
    @discardableResult
    public func add(_ event: TracklessEvent) -> Bool {
        // Non-aggregatable types go to individual list
        if event.type == .funnel || (event.type == .session && event.name != "duration") {
            if totalSize >= maxItems { return false }
            individual.append(event)
            return true
        }

        // Performance events aggregate durations
        if event.type == .performance {
            return addPerformance(event)
        }

        // Count-aggregatable events
        return addCountable(event)
    }

    private func addCountable(_ event: TracklessEvent) -> Bool {
        let key = rollupKey(event)

        if var existing = aggregated[key] {
            existing.count = (existing.count ?? 1) + (event.count ?? 1)
            aggregated[key] = existing
            return true
        }

        if totalSize >= maxItems { return false }

        var newEvent = event
        newEvent.count = event.count ?? 1
        aggregated[key] = newEvent
        return true
    }

    private func addPerformance(_ event: TracklessEvent) -> Bool {
        let key = rollupKey(event)

        if var existing = aggregated[key] {
            var durations = existing.durations ?? []
            if let d = event.duration {
                durations.append(d)
            } else if let ds = event.durations {
                durations.append(contentsOf: ds)
            }
            existing.durations = durations
            existing.duration = nil
            aggregated[key] = existing
            return true
        }

        if totalSize >= maxItems { return false }

        var newEvent = event
        if let d = newEvent.duration {
            newEvent.durations = [d]
            newEvent.duration = nil
        } else if newEvent.durations == nil {
            newEvent.durations = []
        }
        aggregated[key] = newEvent
        return true
    }

    /// Drain the buffer into EventPayloads and clear it.
    public func drain(environment: String, context: EventContext) -> [EventPayload] {
        let allEvents = Array(aggregated.values) + individual
        aggregated.removeAll()
        individual.removeAll()

        guard !allEvents.isEmpty else { return [] }

        let date = dateFormatter.string(from: Date())
        var payloads: [EventPayload] = []

        var i = 0
        while i < allEvents.count {
            let end = min(i + Self.maxEventsPerFlush, allEvents.count)
            let chunk = Array(allEvents[i..<end])
            payloads.append(EventPayload(
                date: date,
                environment: environment,
                context: context,
                events: chunk
            ))
            i = end
        }

        return payloads
    }

    /// Clear the buffer without draining.
    public func clear() {
        aggregated.removeAll()
        individual.removeAll()
    }

    /// Total number of unique items in the buffer.
    public var totalSize: Int {
        aggregated.count + individual.count
    }

    /// Check if the buffer is empty.
    public var isEmpty: Bool {
        totalSize == 0
    }

    /// Build the rollup key for count-aggregatable events.
    private func rollupKey(_ event: TracklessEvent) -> String {
        switch event.type {
        case .feature, .screen:
            return "\(event.type.rawValue)|\(event.name)"
        case .error:
            return "\(event.type.rawValue)|\(event.name)|\(event.severity?.rawValue ?? "")|\(event.code ?? "")"
        case .selection:
            return "\(event.type.rawValue)|\(event.name)|\(event.option ?? "")"
        case .performance:
            return "\(event.type.rawValue)|\(event.name)"
        case .event:
            let propsStr = event.properties.map { props in
                props.sorted(by: { $0.key < $1.key })
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ",")
            } ?? ""
            return "\(event.type.rawValue)|\(event.name)|\(propsStr)"
        case .session:
            return "\(event.type.rawValue)|\(event.name)"
        case .funnel:
            return "\(event.type.rawValue)|\(event.name)|\(event.step ?? "")"
        }
    }
}
