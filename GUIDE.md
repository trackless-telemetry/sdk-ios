# Trackless iOS SDK — Implementation Guide

> This guide is designed for AI coding assistants. Follow the steps exactly to add privacy-first analytics to any iOS or macOS application.

## 1. Install

### Swift Package Manager (Xcode)

**File > Add Package Dependencies**, then enter:

```
https://github.com/trackless-telemetry/sdk-ios
```

Select version `1.0.0` or later. Add `TracklessTelemetry` to your app target.

### Swift Package Manager (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/trackless-telemetry/sdk-ios", from: "1.0.0")
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
        Trackless.configure(TracklessConfig(
            apiKey: "tl_your_api_key_here"
        ))
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
        Trackless.configure(TracklessConfig(
            apiKey: "tl_your_api_key_here"
        ))
        return true
    }
}
```

### Configuration Options

```swift
Trackless.configure(TracklessConfig(
    apiKey: "tl_your_api_key_here",       // Required — API key with tl_ prefix
    endpoint: "https://custom.api.com",   // Optional — defaults to https://api.tracklesstelemetry.com
    environment: .sandbox,                 // Optional — auto-detected from build config
    enabled: true,                         // Optional — set false to disable all recording
    onError: { error in print(error) },    // Optional — error callback for debugging
    flushIntervalSeconds: 60,              // Optional — how often buffered events are sent
    debugLogging: true                     // Optional — enable debug logging via os.Logger
))
```

| Option                  | Type                                  | Default                                | Description                                   |
| ----------------------- | ------------------------------------- | -------------------------------------- | --------------------------------------------- |
| `apiKey`                | `String`                              | **required**                           | API key with `tl_` prefix                     |
| `endpoint`              | `String`                              | `"https://api.tracklesstelemetry.com"` | Ingest endpoint URL                           |
| `environment`           | `TracklessEnvironment?`               | auto-detected                          | `.sandbox` or `.production`                   |
| `enabled`               | `Bool`                                | `true`                                 | Set `false` to disable all recording          |
| `onError`               | `(@Sendable (Error) -> Void)?`        | `nil`                                  | Error callback for debugging                  |
| `flushIntervalSeconds`  | `TimeInterval`                        | `60`                                   | How often buffered events are sent (seconds)  |
| `debugLogging`          | `Bool`                                | `false`                                | Enable debug logging via os.Logger            |

**Environment auto-detection:** In `DEBUG` builds, environment defaults to `.sandbox`. In release builds, it defaults to `.production`. Override by passing `environment:` explicitly.

**App version auto-detection:** `appVersion` and `buildNumber` are automatically read from `Bundle.main` (`CFBundleShortVersionString` and `CFBundleVersion`).

## 3. Track Events

All methods are static. Call them anywhere after `configure()`. Every method is non-blocking, non-throwing, and safe to call from any thread.

### Screen Views

Record when a user views a screen:

```swift
Trackless.screen("home")
Trackless.screen("settings")
Trackless.screen("profile.edit")
```

**When to use:** View appearances, tab switches, navigation destinations.

**SwiftUI — View modifier pattern:**

```swift
extension View {
    func trackScreen(_ name: String) -> some View {
        self.onAppear {
            Trackless.screen(name)
        }
    }
}

// Usage
struct HomeView: View {
    var body: some View {
        VStack { /* ... */ }
            .trackScreen("home")
    }
}
```

**SwiftUI — NavigationStack:**

```swift
struct ContentView: View {
    var body: some View {
        NavigationStack {
            HomeView()
                .trackScreen("home")
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .settings:
                        SettingsView().trackScreen("settings")
                    case .profile:
                        ProfileView().trackScreen("profile")
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
        Trackless.screen("settings")
    }
}
```

### Feature Usage

Record when a user interacts with a feature:

```swift
Trackless.feature("export_clicked")
Trackless.feature("dark_mode_toggled")
Trackless.feature("photo-upload")
Trackless.feature("settings.notifications")
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

Track progression through multi-step flows:

```swift
// Checkout funnel
Trackless.funnel("checkout", step: "view_cart")
Trackless.funnel("checkout", step: "enter_shipping")
Trackless.funnel("checkout", step: "enter_payment")
Trackless.funnel("checkout", step: "confirm_order")
Trackless.funnel("checkout", step: "order_complete")

// Onboarding funnel
Trackless.funnel("onboarding", step: "welcome")
Trackless.funnel("onboarding", step: "create_account")
Trackless.funnel("onboarding", step: "verify_email")
Trackless.funnel("onboarding", step: "complete")
```

**When to use:** Checkout flows, onboarding wizards, multi-step forms — any process where you want to measure drop-off between steps.

**Rules:**
- Step names are deduplicated per session — calling the same step twice is a no-op
- Step index is assigned automatically based on order of first occurrence
- Funnel state resets when the session ends

### Selections

Track choices from a set of options:

```swift
Trackless.selection("theme", option: "dark")
Trackless.selection("sort_order", option: "price_low_to_high")
Trackless.selection("plan", option: "pro_monthly")
Trackless.selection("map_type", option: "satellite")
```

**When to use:** Picker selections, segmented control choices, radio buttons, any place a user picks from a defined set.

### Performance Metrics

Record timing measurements in seconds:

```swift
// Measure API call duration
let start = CFAbsoluteTimeGetCurrent()
let data = try await fetchUserProfile()
Trackless.performance("api_user_profile", duration: CFAbsoluteTimeGetCurrent() - start)

// Measure image processing
let start = CFAbsoluteTimeGetCurrent()
let processed = processImage(original)
Trackless.performance("image_processing", duration: CFAbsoluteTimeGetCurrent() - start)

// App launch time (measure in didFinishLaunchingWithOptions or App.init)
Trackless.performance("app_launch", duration: launchDuration)
```

**When to use:** API latency, image processing time, database query time, app launch time — any timing you want percentile distributions for (p50/p75/p90/p95/p99).

**Important:** Duration is in **seconds** (not milliseconds).

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

All event names follow the same rules:

| Rule | Detail |
|------|--------|
| **Auto-lowercase** | Names are automatically lowercased — `Export_Clicked` becomes `export_clicked` |
| **Characters** | Lowercase `a-z`, digits `0-9`, underscores `_`, hyphens `-`, dots `.` |
| **Length** | 1–100 characters |
| **Dots** | Dots allowed for hierarchical grouping (e.g., `settings.theme`, `nav.settings.display`) |
| **No identifiers** | UUIDs, long hex strings, and numeric-only strings >12 chars are rejected |

**Valid:** `checkout_started`, `settings.dark_mode`, `photo-upload`, `nav.settings.display`
**Also valid (auto-lowercased):** `Export_Clicked` → `export_clicked`, `Settings.Theme` → `settings.theme`
**Invalid:** `user 123` (space), `.leading-dot` (leading dot), `export!clicked` (special characters)

### Hierarchical Grouping with Dots

Use `.` delimiters to create hierarchical event names. The dashboard groups **feature** events by the first dot segment and shows donut charts with the distribution of values within each group.

```swift
// These create a "theme" group in the dashboard with "dark" and "light" values
Trackless.feature("theme.dark")
Trackless.feature("theme.light")

// Deeper hierarchies work too — grouped by first segment ("settings")
Trackless.feature("settings.display.theme")
Trackless.feature("settings.display.layout")
Trackless.feature("settings.notifications")
```

**Which types support grouping?** Dots are allowed in names for all event types, but the dashboard's automatic group visualization (donut charts) currently applies to **`feature`** events only. For other use cases, consider the typed alternatives:

- Instead of `feature("theme.dark")` / `feature("theme.light")` → use `selection("theme", "dark")` for choice-from-a-set scenarios
- Use `feature` with dots when you want the dashboard group charts, or when the variants aren't mutually exclusive choices

## 5. Session Lifecycle

Sessions are managed automatically. No code needed.

- **Start:** A session begins when `Trackless.configure()` is called
- **End:** A session ends when the app enters the background (via `willResignActive`)
- **Resume vs. new session:** If the app returns to the foreground within 30 minutes, the existing session continues. After 30 minutes in the background, the old session ends and a new one starts on `didBecomeActive`.
- **Depth:** Every non-session event increments the session's depth counter
- **Duration:** Measured from session start to session end
- **Context:** `daysSinceInstall` is computed from the Documents directory creation date (read-only, no disk writes)

## 6. Flush Behavior

Events are buffered in memory and sent in batches:

- **Periodic flush:** Every 60 seconds if the buffer is non-empty
- **Item threshold:** When the buffer reaches 100 unique items
- **Session end:** Flushed when the app backgrounds (using `UIApplication.beginBackgroundTask`)
- **Manual:** Call `await Trackless.flush()` at any time
- **Client-side rollup:** Duplicate events are pre-aggregated (e.g., 50 `feature("save")` calls become one event with `count: 50`)
- **Circuit breaker:** Server errors trigger exponential backoff (30s → 60s → 5m → 15m → 60m)

## 7. Runtime Controls

```swift
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
        Trackless.configure(TracklessConfig(
            apiKey: "tl_abc123def456"
        ))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                HomeView()
                    .trackScreen("home")
                    .tabItem { Label("Home", systemImage: "house") }
                SearchView()
                    .trackScreen("search")
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                CartView()
                    .trackScreen("cart")
                    .tabItem { Label("Cart", systemImage: "cart") }
                ProfileView()
                    .trackScreen("profile")
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
                    duration: CFAbsoluteTimeGetCurrent() - start
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
                    Trackless.funnel("checkout", step: "view_cart")
                    step = .shipping
                })
            case .shipping:
                ShippingForm(onSelect: { method in
                    Trackless.selection("shipping_method", option: method)
                    Trackless.funnel("checkout", step: "enter_shipping")
                    step = .payment
                })
            case .payment:
                PaymentForm(onSubmit: {
                    Trackless.funnel("checkout", step: "enter_payment")
                    submitOrder()
                })
            case .confirmation:
                OrderConfirmation()
                    .onAppear {
                        Trackless.funnel("checkout", step: "order_complete")
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
                    duration: CFAbsoluteTimeGetCurrent() - start
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
                Trackless.selection("theme", option: newValue)
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
        .trackScreen("settings")
    }
}
```

## 9. Privacy Guarantees

Trackless collects **no user identifiers** and stores **only aggregate counts**:

- **No IDFA or IDFV** — no App Tracking Transparency prompt needed
- **No device name, model, or hardware identifiers**
- **No IP address processing** — region comes from system locale, not IP geolocation
- **No persistent storage** — no UserDefaults, Keychain, files, or Core Data
- **No cross-session linking** — session state is in-memory only
- **No data sent to third parties** — events go only to your configured endpoint
- **PII auto-redaction** on custom event properties

The only context collected is: platform (`"ios"`), OS version (major.minor), device class (phone/tablet/desktop), locale (from `Locale.current`), app version, build number, and days since install. All are coarse, non-identifying dimensions.

## 10. API Key Management

Store the API key securely. Do **not** hardcode it in source files committed to version control.

**Recommended approaches:**

1. **Xcode build configuration:**
   ```swift
   // Define in xcconfig or Info.plist
   let apiKey = Bundle.main.infoDictionary?["TRACKLESS_API_KEY"] as? String ?? ""
   Trackless.configure(TracklessConfig(apiKey: apiKey))
   ```

2. **Environment-based:**
   ```swift
   #if DEBUG
   let apiKey = "tl_sandbox_key_here"
   #else
   let apiKey = "tl_production_key_here"
   #endif
   Trackless.configure(TracklessConfig(apiKey: apiKey))
   ```
