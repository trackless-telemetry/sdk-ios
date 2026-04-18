# Trackless iOS SDK — Implementation Guide

> This guide is designed for AI coding assistants. Follow the steps exactly to add privacy-first analytics to any iOS or macOS application.

## 1. Install

### Swift Package Manager (Xcode)

**File > Add Package Dependencies**, then enter:

```
https://github.com/trackless-telemetry/sdk-ios
```

Select version `0.2.4` or later. Add `TracklessTelemetry` to your app target.

### Swift Package Manager (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/trackless-telemetry/sdk-ios", from: "0.2.4")
]
```

Add to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "TracklessTelemetry", package: "sdk-ios")
    ]
)
```

**Requirements:** iOS 15+ / macOS 12+, Swift 6.0+, Xcode 16+. Zero external dependencies.

## 2. Configure

Call `Trackless.configure()` once at app launch — before any events are recorded.

### SwiftUI App

```swift
import SwiftUI
import TracklessTelemetry

@main
struct MyApp: App {
    init() {
        Trackless.configure(apiKey: "tl_your_api_key_here")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### UIKit AppDelegate

```swift
import UIKit
import TracklessTelemetry

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        Trackless.configure(apiKey: "tl_your_api_key_here")
        return true
    }
}
```

### Configuration Options

```swift
Trackless.configure(
    apiKey: "tl_your_api_key_here",       // Required — API key with tl_ prefix
    endpoint: "https://custom.api.com",   // Optional — defaults to https://api.tracklesstelemetry.com
    environment: .sandbox,                 // Optional — auto-detected from build config
    enabled: true,                         // Optional — set false to disable all recording
    onError: { error in print(error) },    // Optional — error callback for debugging
    flushIntervalSeconds: 60,              // Optional — how often buffered events are sent
    debugLogging: true,                    // Optional — enable debug logging for happy-path events
    suppressWarnings: false                // Optional — suppress warning and error logging
)
```

| Option                  | Type                                  | Default                                | Description                                   |
| ----------------------- | ------------------------------------- | -------------------------------------- | --------------------------------------------- |
| `apiKey`                | `String`                              | **required**                           | API key with `tl_` prefix                     |
| `endpoint`              | `String`                              | `"https://api.tracklesstelemetry.com"` | Ingest endpoint URL                           |
| `environment`           | `TracklessEnvironment?`               | auto-detected                          | `.sandbox` or `.production`                   |
| `enabled`               | `Bool`                                | `true`                                 | Set `false` to disable all recording          |
| `onError`               | `(@Sendable (Error) -> Void)?`        | `nil`                                  | Error callback for debugging                  |
| `flushIntervalSeconds`  | `TimeInterval`                        | `60`                                   | How often buffered events are sent (seconds)  |
| `debugLogging`          | `Bool`                                | `false`                                | Enable debug logging for happy-path events    |
| `suppressWarnings`      | `Bool`                                | `false`                                | Suppress warning and error logging            |

**Environment auto-detection:** In `DEBUG` builds, environment defaults to `.sandbox`. In release builds, it defaults to `.production`. Override by passing `environment:` explicitly.

**App version auto-detection:** `appVersion` and `buildNumber` are automatically read from `Bundle.main` (`CFBundleShortVersionString` and `CFBundleVersion`).

## 3. Track Events

All methods are static. Call them anywhere after `configure()`. Every method is non-blocking, non-throwing, and safe to call from any thread.

### Views

Record when a user views a screen, with an optional detail:

```swift
Trackless.view("home")
Trackless.view("settings")
Trackless.view("profile.edit")
Trackless.view("settings", detail: "notifications")  // with detail
```

**When to use:** View appearances, tab switches, navigation destinations.

**SwiftUI — View modifier pattern:**

```swift
extension View {
    func trackView(_ name: String) -> some View {
        self.onAppear {
            Trackless.view(name)
        }
    }
}

// Usage
struct HomeView: View {
    var body: some View {
        VStack { /* ... */ }
            .trackView("home")
    }
}
```

**SwiftUI — NavigationStack:**

```swift
struct ContentView: View {
    var body: some View {
        NavigationStack {
            HomeView()
                .trackView("home")
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .settings:
                        SettingsView().trackView("settings")
                    case .profile:
                        ProfileView().trackView("profile")
                    }
                }
        }
    }
}
```

**UIKit — UIViewController:**

```swift
class SettingsViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Trackless.view("settings")
    }
}
```

### Feature Usage

Record when a user interacts with a feature:

```swift
Trackless.feature("export_clicked")
Trackless.feature("dark_mode_toggled")
Trackless.feature("photo-upload")
Trackless.feature("settings", detail: "notifications")
```

**When to use:** Button taps, toggle switches, user-initiated actions.

**SwiftUI button example:**

```swift
Button("Export Data") {
    Trackless.feature("export_data")
    exportData()
}
```

### Funnel Steps

Track progression through multi-step flows. Each step has a developer-defined index (0-based) that determines its position in the funnel:

```swift
// Checkout funnel
Trackless.funnel("checkout", stepIndex: 0, step: "view_cart")
Trackless.funnel("checkout", stepIndex: 1, step: "enter_shipping")
Trackless.funnel("checkout", stepIndex: 2, step: "enter_payment")
Trackless.funnel("checkout", stepIndex: 3, step: "confirm_order")
Trackless.funnel("checkout", stepIndex: 4, step: "order_complete")

// Onboarding funnel
Trackless.funnel("onboarding", stepIndex: 0, step: "welcome")
Trackless.funnel("onboarding", stepIndex: 1, step: "create_account")
Trackless.funnel("onboarding", stepIndex: 2, step: "verify_email")
Trackless.funnel("onboarding", stepIndex: 3, step: "complete")
```

**When to use:** Checkout flows, onboarding wizards, multi-step forms — any process where you want to measure drop-off between steps.

**Rules:**
- Step index is developer-defined (0-based) and determines the order of steps in funnel charts
- Steps are deduplicated per session — calling the same step index twice is a no-op
- Funnel state resets when the session ends

### Performance Metrics

Record timing measurements in seconds, with an optional **threshold** for breach tracking:

```swift
// Measure API call duration
let start = CFAbsoluteTimeGetCurrent()
let data = try await fetchUserProfile()
Trackless.performance("api_user_profile", durationSeconds: CFAbsoluteTimeGetCurrent() - start)

// Measure image processing
let start = CFAbsoluteTimeGetCurrent()
let processed = processImage(original)
Trackless.performance("image_processing", durationSeconds: CFAbsoluteTimeGetCurrent() - start)

// App launch time (measure in didFinishLaunchingWithOptions or App.init)
Trackless.performance("app_launch", durationSeconds: launchDuration)

// With threshold — track how many measurements exceed 2 seconds
Trackless.performance("api_user_profile", durationSeconds: elapsed, thresholdSeconds: 2.0)
```

**When to use:** API latency, image processing time, database query time, app launch time — any timing you want percentile distributions for (p50/p90/p99).

**Threshold:** The optional `threshold` parameter defines a performance threshold in seconds. Each name/threshold combination is tracked separately, with breach counts shown in the dashboard.

**Important:** Duration is in **seconds** (not milliseconds). Threshold must be > 0.

### Errors

Record application errors with severity and optional code:

```swift
// Basic error
Trackless.error("payment_failed", severity: .error)

// With error code
Trackless.error("api_timeout", severity: .warning, code: "ETIMEDOUT")
Trackless.error("validation_failed", severity: .info, code: "INVALID_EMAIL")

// In a catch block
do {
    try await submitOrder()
} catch {
    Trackless.error("order_submission", severity: .error, code: String(describing: type(of: error)))
}
```

**Severity levels:** `.debug`, `.info`, `.warning`, `.error`, `.fatal`

**When to use:** Caught exceptions, failed network requests, validation errors, any error you want to trend over time.

## 4. Event Naming Rules

All event fields (`name`, `detail`, `step`, `code`) are automatically normalized before buffering:

| Rule | Detail |
|------|--------|
| **Auto-lowercase** | Fields are lowercased — `Export_Clicked` becomes `export_clicked` |
| **Auto-normalize** | Spaces and invalid characters are replaced with `_` — `Sign Up Button` becomes `sign_up_button` |
| **Trim** | Leading/trailing underscores and dots are removed — `...foo...` becomes `foo` |
| **Collapse dots** | Consecutive dots are collapsed — `foo..bar` becomes `foo.bar` |
| **Truncate** | Truncated to 100 characters |
| **No identifiers** | UUIDs, long hex strings, and numeric-only strings >12 chars are rejected |
| **PII stripping** | Emails, phone numbers, and SSN patterns are stripped from all fields |

**Valid characters after normalization:** Lowercase `a-z`, digits `0-9`, underscores `_`, hyphens `-`, dots `.`

**Examples:** `"Sign Up Button"` → `"sign_up_button"`, `"ERR_001"` → `"err_001"`, `"Export!Clicked"` → `"export_clicked"`, `"Settings.Theme"` → `"settings.theme"`

### Feature Grouping with Detail

Use the optional `detail` parameter to distinguish variants within a feature. The dashboard groups features that have detail values and shows donut charts with the distribution.

```swift
// These create a "theme" group in the dashboard with "dark" and "light" values
Trackless.feature("theme", detail: "dark")
Trackless.feature("theme", detail: "light")

// Use detail for any choice-from-a-set scenario
Trackless.feature("distance_preset", detail: "1_mile")
Trackless.feature("distance_preset", detail: "2_miles")
Trackless.feature("settings", detail: "notifications")
```

**Which types support grouping?** The `detail` parameter is supported on `feature` and `view` events. The dashboard's automatic group visualization (donut charts) applies to both.

## 5. Session Lifecycle

Sessions are managed automatically. No code needed.

- **Start:** A session begins when `Trackless.configure()` is called, and a new session starts each time the app returns to the foreground
- **End:** A session ends when the app enters the background — the session-end event (with duration and depth) is flushed immediately
- **Depth:** Every non-session event increments the session's depth counter
- **Duration:** Measured from session start to session end
- **Context:** `daysSinceInstall` is computed from the Documents directory creation date (read-only, no disk writes)

## 6. Flush Behavior

Events are buffered in memory and sent in batches:

- **Periodic flush:** Every 60 seconds if the buffer is non-empty
- **Item thresholdSeconds:** When the buffer reaches 100 unique items
- **Session end:** Flushed when the app backgrounds (using `UIApplication.beginBackgroundTask`)
- **Manual:** Call `await Trackless.flush()` at any time
- **Client-side rollup:** Duplicate events are pre-aggregated (e.g., 50 `feature("save")` calls become one event with `count: 50`)
- **Circuit breaker:** Server errors trigger exponential backoff (30s → 60s → 5m → 15m → 60m)

## 7. Runtime Controls

```swift
// Check if the SDK is configured (useful in shared/library code)
if await Trackless.isConfigured {
    Trackless.feature("shared_action")
}

// Disable recording (e.g., user opts out)
Trackless.setEnabled(false)   // Discards buffer, stops timers

// Re-enable recording
Trackless.setEnabled(true)    // Resumes from empty buffer

// Force flush
await Trackless.flush()

// Permanent shutdown
await Trackless.destroy()     // Flushes remaining events, then disables permanently
```

## 8. Complete Integration Example

### SwiftUI App with All Event Types

```swift
import SwiftUI
import TracklessTelemetry

@main
struct ShopApp: App {
    init() {
        Trackless.configure(apiKey: "tl_abc123def456")
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                HomeView()
                    .trackView("home")
                    .tabItem { Label("Home", systemImage: "house") }
                SearchView()
                    .trackView("search")
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                CartView()
                    .trackView("cart")
                    .tabItem { Label("Cart", systemImage: "cart") }
                ProfileView()
                    .trackView("profile")
                    .tabItem { Label("Profile", systemImage: "person") }
            }
        }
    }
}
```

```swift
// SearchView.swift
struct SearchView: View {
    @State private var query = ""
    @State private var results: [Product] = []

    var body: some View {
        VStack {
            TextField("Search...", text: $query)
                .onSubmit { performSearch() }

            ForEach(results) { product in
                ProductRow(product: product)
            }
        }
    }

    func performSearch() {
        Trackless.feature("search_executed")
        let start = CFAbsoluteTimeGetCurrent()

        Task {
            do {
                results = try await searchProducts(query)
                Trackless.performance(
                    "search_api",
                    durationSeconds: CFAbsoluteTimeGetCurrent() - start
                )
            } catch {
                Trackless.error("search_failed", severity: .error)
            }
        }
    }
}
```

```swift
// CheckoutFlow.swift
struct CheckoutFlow: View {
    @State private var step: CheckoutStep = .cart

    var body: some View {
        NavigationStack {
            switch step {
            case .cart:
                CartSummary(onContinue: {
                    Trackless.funnel("checkout", stepIndex: 0, step: "view_cart")
                    step = .shipping
                })
            case .shipping:
                ShippingForm(onSelect: { method in
                    Trackless.feature("shipping_method", detail: method)
                    Trackless.funnel("checkout", stepIndex: 1, step: "enter_shipping")
                    step = .payment
                })
            case .payment:
                PaymentForm(onSubmit: {
                    Trackless.funnel("checkout", stepIndex: 2, step: "enter_payment")
                    submitOrder()
                })
            case .confirmation:
                OrderConfirmation()
                    .onAppear {
                        Trackless.funnel("checkout", stepIndex: 3, step: "order_complete")
                    }
            }
        }
    }

    func submitOrder() {
        let start = CFAbsoluteTimeGetCurrent()
        Task {
            do {
                try await placeOrder()
                Trackless.performance(
                    "order_submission",
                    durationSeconds: CFAbsoluteTimeGetCurrent() - start
                )
                step = .confirmation
            } catch {
                Trackless.error(
                    "order_failed",
                    severity: .error,
                    code: String(describing: type(of: error))
                )
            }
        }
    }
}
```

```swift
// SettingsView.swift
struct SettingsView: View {
    @AppStorage("theme") private var theme = "system"

    var body: some View {
        Form {
            Picker("Theme", selection: $theme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .onChange(of: theme) { _, newValue in
                Trackless.feature("theme", detail: newValue)
            }

            Button("Export Data") {
                Trackless.feature("data_export")
                exportData()
            }

            Button("Clear Cache") {
                Trackless.feature("clear_cache")
                clearCache()
            }
        }
        .trackView("settings")
    }
}
```

## 9. Privacy Guarantees

Trackless collects **no user identifiers** and stores **only aggregate counts**:

- **No IDFA or IDFV** — no App Tracking Transparency prompt needed
- **No device name, model, or hardware identifiers**
- **No IP address processing by application code** — IP addresses are never read, parsed, stored, or used by the SDK or the Trackless backend. Region comes from system locale, not IP geolocation. (AWS infrastructure receives IP addresses for network routing and DDoS protection as part of standard cloud operations, but they are not used for analytics.)
- **No persistent storage** — no UserDefaults, Keychain, files, or Core Data
- **No cross-session linking** — session state is in-memory only
- **No data sent to third parties** — events go only to your configured endpoint
- **No stack traces, crash logs, or error messages** — error tracking uses only developer-defined names, severity levels, and codes
- **No individual performance measurements stored** — durations are aggregated server-side into statistical digests (t-digest)
- **PII auto-stripping** — email addresses, phone numbers, and SSN patterns are automatically stripped from all event fields before buffering

The only context collected is: platform (`"ios"`), OS version (major only, e.g., `"17"`), device class (phone/tablet/desktop), region (two-letter country code from `Locale.current`, e.g., `"US"`), language (ISO 639-1 code from `Locale.current`, e.g., `"en"`), app version, build number, days since install, and `sdkVersion` (automatically included, e.g., `"ios/0.2.4"`), and distribution channel (automatically detected: `"testflight"`, `"app_store"`, `"debug"`, or `"unknown"`). All are coarse, non-identifying dimensions.

### App Store Privacy Labels

When submitting to the App Store, declare the following in App Store Connect (all **Not Linked to User Identity**, **Not Used for Tracking**):

| Category | Data Type | Why |
|----------|-----------|-----|
| Usage Data | Product Interaction | Feature counts, view counts, funnel steps |
| Diagnostics | Crash Data | Error events (name, severity, code — no stack traces) |
| Diagnostics | Performance Data | Performance metrics (duration digest — no individual measurements) |

ATT is **not required**. See [Section 22.7 of the SDK requirements](https://github.com/trackless-telemetry/platform/blob/main/docs/requirements/sdks.md#227-app-store-privacy-compliance-guidance) for full guidance.

## 10. API Key Management

Store the API key securely. Do **not** hardcode it in source files committed to version control.

**Recommended approaches:**

1. **Xcode build configuration:**
   ```swift
   // Define in xcconfig or Info.plist
   let apiKey = Bundle.main.infoDictionary?["TRACKLESS_API_KEY"] as? String ?? ""
   Trackless.configure(apiKey: apiKey)
   ```

2. **Environment-based:**
   ```swift
   #if DEBUG
   let apiKey = "tl_sandbox_key_here"
   #else
   let apiKey = "tl_production_key_here"
   #endif
   Trackless.configure(apiKey: apiKey)
   ```
