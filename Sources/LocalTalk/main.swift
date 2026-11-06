import AppKit

// Top-level code runs on the main thread; AppDelegate is @MainActor.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
