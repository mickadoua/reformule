import AppKit

@MainActor var app: App!

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--pasteboard") {
        Task {
            do {
                let correction = try await correct(.general, Settings.options)
                write(correction.item, to: .general)
                print("blocs laissés tel quel : \(correction.failures)")
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
