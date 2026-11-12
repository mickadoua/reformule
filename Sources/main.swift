import AppKit

@MainActor var app: App!

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--pasteboard") {
        Task {
            do {
                print("blocs laissés tel quel : \(try await rewritePasteboard(.general, Settings.options))")
                exit(0)
            } catch {
                print(error.localizedDescription)
                exit(1)
            }
        }
    } else {
        app = App()
        NSApplication.shared.delegate = app
    }
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.run()
}
