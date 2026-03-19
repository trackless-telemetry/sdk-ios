# Trackless Telemetry iOS SDK

Privacy-first analytics for iOS apps. Record what features your users use — without tracking who they are.

Trackless collects **aggregate usage counts** with coarse device context. No user identifiers. No fingerprinting. No persistent storage. Fully compliant with GDPR, CCPA, PECR, and ePrivacy — with nothing to consent to.

## Requirements

- iOS 15+ / macOS 12+
- Swift 6.0+
- Xcode 16+

## Installation

### Swift Package Manager

Add the package in Xcode: **File > Add Package Dependencies**, then enter:

```
https://github.com/trackless-telemetry/sdk-ios
```

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/trackless-telemetry/sdk-ios", from: "0.2.0")
]
```

Then add `"TracklessTelemetry"` to your target's dependencies:

```swift
.target(
    name: "MyApp",
    dependencies: ["TracklessTelemetry"]
)
```

## Quick Start

```swift
import TracklessTelemetry

// Initialize once (e.g., in your @main App init or AppDelegate)
Trackless.configure(apiKey: "tl_your_api_key_here")

// Record events anywhere in your app
Trackless.view("home")
Trackless.view("settings", detail: "profile")
Trackless.feature("export_clicked")
Trackless.feature("export_clicked", detail: "csv")
Trackless.funnel("checkout", stepIndex: 0, step: "view_cart")
Trackless.performance("api_fetch", durationSeconds: 0.342)
Trackless.error("payment_failed", severity: .error, code: "DECLINED")
```

## API Reference

### Configuration

```swift
// Simple — just an API key with default settings
Trackless.configure(apiKey: "tl_your_api_key_here")

// All options
Trackless.configure(
    apiKey: "tl_your_api_key_here",
    endpoint: "https://custom.api.com",    // Optional — defaults to https://api.tracklesstelemetry.com
    environment: .sandbox,                  // Optional — auto-detected from build config
    enabled: true,                          // Optional — disable to suppress all recording
    onError: { error in print(error) },     // Optional — callback for debugging
    flushIntervalSeconds: 60,              // Optional — how often buffered events are sent
    debugLogging: false,                   // Optional — enable debug logging for happy-path events
    suppressWarnings: false                // Optional — suppress warning and error logging
)
```

**Environment auto-detection:** Debug builds automatically use `.sandbox`, release builds use `.production`. Override by passing `environment:` explicitly.

**App version auto-detection:** `appVersion` and `buildNumber` are automatically read from `Bundle.main`.

### Event Methods

All methods are static, non-blocking, non-throwing, and safe to call from any thread.

| Method | Description |
|--------|-------------|
| `Trackless.view(_ name: String, detail: String?)` | View event (optional detail) |
| `Trackless.feature(_ name: String, detail: String?)` | Feature interaction (optional detail) |
| `Trackless.funnel(_ funnelName: String, stepIndex: Int, step: String)` | Funnel step progression |
| `Trackless.performance(_ name: String, durationSeconds: Double, thresholdSeconds: Double?)` | Timing measurement (seconds) |
| `Trackless.error(_ name: String, severity: ErrorSeverity, code: String?)` | Application error |

### Control Methods

```swift
await Trackless.isConfigured // Check if SDK is ready (useful in shared code)

Trackless.setEnabled(false)  // Stop recording, discard buffer
Trackless.setEnabled(true)   // Resume recording

await Trackless.flush()      // Force-send buffered events
await Trackless.destroy()    // Flush and permanently disable
```

## Event Naming Rules

- **Auto-lowercase:** names are automatically lowercased (`Export_Clicked` → `export_clicked`)
- **Characters:** lowercase letters, numbers, underscores, hyphens, and dots (`[a-z0-9_.-]`)
- **Length:** 1–100 characters
- **Dots:** dots allowed for hierarchical grouping (e.g., `settings.theme`, `nav.settings.display`)
- **No identifiers:** UUIDs, long hex strings, and long numeric strings are rejected

## How It Works

1. **Buffering** — Events are aggregated in memory. Duplicate events increment a counter rather than creating separate entries.
2. **Periodic flush** — Every 60 seconds (configurable), the buffer is sent to the ingest endpoint as a batch.
3. **Background flush** — The SDK flushes when the app enters the background using a `UIBackgroundTask`.
4. **Session management** — Sessions start on configure and on each foreground return, end on background with immediate flush.
5. **Circuit breaker** — Server errors trigger exponential backoff (30s → 60s → 5m → 15m → 60m).
6. **Bounded memory** — Buffer holds up to 1,000 unique entries. Beyond that, new entries are silently dropped.

## Context Collected

The SDK captures a small set of **coarse, non-identifying** dimensions:

| Dimension | Example | Source |
|-----------|---------|--------|
| `platform` | `"ios"` | Compile-time constant |
| `osVersion` | `"17"` | `ProcessInfo` (major only) |
| `deviceClass` | `"phone"`, `"tablet"`, `"desktop"` | `UIDevice.userInterfaceIdiom` |
| `region` | `"US"` | `Locale.current` (country code) |
| `appVersion` | `"2.1.0"` | `Bundle.main` |
| `buildNumber` | `"142"` | `Bundle.main` |
| `daysSinceInstall` | `45` | Documents directory creation date |

## What Trackless Does NOT Collect

- No IDFA or IDFV — no App Tracking Transparency prompt needed
- No device name, model, or hardware identifiers
- No IP-based geolocation (region comes from system locale settings)
- No persistent storage (no UserDefaults, Keychain, files, or Core Data)
- No cross-session linking of any kind
- No data sent to third parties
- PII auto-stripping of email addresses, phone numbers, and SSN patterns from all event fields

## Thread Safety

`Trackless` is fully `Sendable` and safe to use from any thread or Swift concurrency context. Internal state is managed via Swift actors.

## License

MIT License. See [LICENSE](LICENSE) for details.
