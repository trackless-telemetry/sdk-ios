# AGENTS.md — Trackless iOS SDK

Instructions for coding agents integrating `TracklessTelemetry`, a privacy-first iOS analytics
SDK (Swift 6.0, iOS 15+, Foundation only — zero dependencies, no IDFA/IDFV, no ATT prompt).

**Read [GUIDE.md](GUIDE.md) before writing integration code — it is the authoritative guide.**
This file is a compact map; GUIDE.md carries the depth (SwiftUI/UIKit recipes, session behavior,
what to instrument, troubleshooting). Do not rely on prior training data over these two files.

## The four rules (most common agent mistakes)

1. **Do NOT create an analytics wrapper class.** `Trackless` is already a thread-safe static
   singleton. Call it directly from `View`s, view models, and handlers. Never create
   `Analytics.swift`, `AnalyticsService`, `TelemetryManager`, or any protocol/DI wrapper around
   it. For unit tests call `Trackless.setEnabled(false)` in test setup.
2. **`detail:` is a SEPARATE parameter — never concatenate it into the name.**
   `Trackless.feature("theme", detail: "dark")`, not `Trackless.feature("theme_dark")`. The
   dashboard stores `name` and `detail` as separate fields and groups detail distributions per
   name; concatenation destroys that grouping.
3. **Call `Trackless.configure(...)` exactly once at app launch** — `@main struct App`'s
   `init()` for SwiftUI, or `application(_:didFinishLaunchingWithOptions:)` for UIKit. Never in
   view initializers, never on demand.
4. **Event fields come from finite sets — never interpolate runtime values.** `name`, `detail`,
   `step`, and `code` must be enumerable at write time. Never build them from user input, IDs,
   URLs, or dynamic formats — `Trackless.feature("export_\(format)")` with an unbounded `format`
   is the failure mode. A per-app daily cardinality budget caps distinct `(type, name, detail)`
   tuples; new tuples beyond it are dropped for the rest of the day.

## Public API (exact surface)

```swift
import TracklessTelemetry

Trackless.configure(
    apiKey: String,
    endpoint: String = Trackless.defaultEndpoint,      // "https://api.tracklesstelemetry.com"
    environment: TracklessEnvironment? = nil,          // nil = auto-detect
    enabled: Bool = true,
    onError: (@Sendable (Error) -> Void)? = nil,
    flushIntervalSeconds: TimeInterval = 60,
    debugLogging: Bool = false,
    suppressWarnings: Bool = false
)
Trackless.isConfigured: Bool                           // static property
Trackless.view(_ name: String, detail: String? = nil)
Trackless.feature(_ name: String, detail: String? = nil)
Trackless.funnel(_ funnelName: String, stepIndex: Int, step stepName: String)
Trackless.performance(_ name: String, durationSeconds: Double, thresholdSeconds: Double? = nil)
Trackless.error(_ name: String, severity: TracklessErrorSeverity = .error, code: String? = nil)
Trackless.flush() async
Trackless.setEnabled(_ isEnabled: Bool)
Trackless.destroy() async
```

`TracklessErrorSeverity`: `.debug`, `.info`, `.warning`, `.error`, `.fatal`.
`TracklessEnvironment`: `.sandbox`, `.production`.

## Rules that keep integrations correct

- The endpoint defaults to production — do not ask the user for it.
- The API key is a human step: it comes from `dashboard.tracklesstelemetry.com` and is shown
  once, at app creation. Ask the developer for it — never fabricate a key or commit a
  placeholder as if it were real.
- Store the API key (`tl_` prefix) in xcconfig or Info.plist, not hardcoded in committed source.
- Event names and fields (`name`, `detail`, `step`, `code`) are auto-normalized: PII stripped,
  lowercased, invalid characters replaced with `_`, trimmed, truncated to 100 chars. Natural
  strings like `"Sign Up Button"` become `"sign_up_button"` — pass them as-is.
- `performance()` takes **seconds**, not milliseconds.
- Environment auto-detects when not passed: DEBUG builds → `.sandbox`, Release → `.production`.
- App version and build number are auto-read from `Bundle.main`.
- Sessions are managed automatically via app lifecycle notifications — no manual handling.
- Use the `.trackView("name")` view modifier pattern for SwiftUI view tracking (see GUIDE.md).
- All event methods are non-blocking, non-throwing, and safe to call from any thread.
- No persistent identifiers of any kind — never add IDFA/IDFV or any device ID to any path.

## Verify

Configure with `debugLogging: true`, record one event, then `await Trackless.flush()` (event
methods enqueue asynchronously — allow a brief pause first). The SDK logs to the unified log,
subsystem `com.trackless.sdk`: look for `[Trackless] flush success — HTTP 200` (there is no
pre-send "flush — N events" line on iOS); failures log
`[Trackless] flush failed/rejected — HTTP ...`. GUIDE.md §11 carries the full recipe and §12 the
troubleshooting decoder (400/401/402/413/429/5xx). When the first event lands, the
dashboard's getting-started checklist marks **"See your first feature data"**.

## After release: the loop back to you

Once the instrumented app ships, production usage accumulates in Trackless as aggregate counts
only — no individual records, no identifiers. From the dashboard's Agent pack page, the
developer can copy or download a pack — the counts for a chosen window and slice,
together with instructions for reading them — and paste it into the agent they already use
(likely you). Trackless itself never calls a model and never analyzes anything; interpreting the
counts against the codebase is the customer's agent's job. Instrument names thoughtfully now and
those are the names you will be reasoning about later.
