import AppKit
import Carbon.HIToolbox
import SwiftUI

final class ActionItem: NSMenuItem {
    let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc func fire() { handler() }
}

@MainActor final class App: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    var statusItem: NSStatusItem!
    let hud = Hud()
    let card = SuggestionCard()
    @Published var hotKey = Settings.hotKey
    @Published var status = "Prêt"
    @Published var recording = false
    @Published var recordingProblem: String?
    var recorder: Any?
    var busy = false
    var serviceResult: Result<Int, any Error>?

    lazy var settingsWindow: NSWindow = {
        let controller = NSHostingController(rootView: SettingsView(app: self))
        controller.sceneBridgingOptions = [.title, .toolbars]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 720, height: 500))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = icon(busy: false)
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if !installKeyTap() {
            status = "En attente de l'autorisation Accessibilité"
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
                guard installKeyTap() else { return }
                timer.invalidate()
                Task { @MainActor in app.report("Prêt", beep: false) }
            }
        }
        buildMenu()
    }

    // A full menu bar hides the icon behind the notch, so opening the app again shows its settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationDidResignActive(_ notification: Notification) { stopRecording() }

    func windowWillClose(_ notification: Notification) { stopRecording() }

    func showSettings() {
        NSApp.activate()
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    func icon(busy: Bool) -> NSImage? {
        NSImage(systemSymbolName: busy ? "ellipsis.circle" : "pencil.and.scribble", accessibilityDescription: "Reformule")
    }

    func buildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(ActionItem("Réglages…", key: ",") { self.showSettings() })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter Reformule", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func report(_ message: String, beep: Bool = true) {
        status = message
        if beep { NSSound.beep() }
        buildMenu()
    }

    // Recording reads keys from the settings window, so it works before Accessibility is granted.
    func startRecording() {
        recordingProblem = nil
        recording = true
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let cgEvent = event.cgEvent {
                let key = HotKey(cgEvent)
                MainActor.assumeIsolated { self.record(key) }
            }
            return nil
        }
    }

    func record(_ key: HotKey) {
        if key.keyCode == Int64(kVK_Escape) {
            stopRecording()
        } else if let problem = key.problem {
            recordingProblem = problem
        } else {
            hotKey = key
            Settings.hotKey = key
            stopRecording()
        }
    }

    func stopRecording() {
        if let recorder { NSEvent.removeMonitor(recorder) }
        recorder = nil
        recording = false
        recordingProblem = nil
    }

    func handle(_ event: CGEvent) -> Bool {
        if card.isOpen {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if card.isReady, code == Int64(kVK_Return) || code == Int64(kVK_ANSI_KeypadEnter), event.flags.isDisjoint(with: HotKey.modifierMask) {
                card.resolve(true)
                return true
            }
            card.dismiss()
            return code == Int64(kVK_Escape) || hotKey.matches(event)
        }
        guard !recording, hotKey.matches(event) else { return false }
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { Task { await run() } }
        return true
    }

    func run() async {
        guard !busy else { return }
        guard AXIsProcessTrusted() else { return report("Autoriser Reformule dans Réglages > Confidentialité et sécurité > Accessibilité") }
        busy = true
        statusItem.button?.image = icon(busy: true)
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
        let restore = {
            pasteboard.clearContents()
            pasteboard.writeObjects(saved.map { entries in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            })
        }
        let target = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var outcome = "Corrigé"
        var problem: String?
        do {
            try await waitForModifiersRelease()
            var count = pasteboard.changeCount
            try press("c")
            let hadSelection = try await copied(pasteboard, since: count, within: 15)
            if !hadSelection {
                try press("a")
                try await Task.sleep(for: .milliseconds(80))
                count = pasteboard.changeCount
                try press("c")
                guard try await copied(pasteboard, since: count, within: 50) else { throw Failure("Rien n'a été copié") }
            }
            card.show(at: selectionAnchor())
            let correction = try await correct(pasteboard, Settings.options)
            restore()
            if card.cancelled {
                outcome = "Annulé"
            } else if correction.before == correction.after {
                outcome = "Rien à corriger"
                hud.show(outcome, busy: false)
                hud.hide(after: .seconds(1.5))
            } else {
                let (text, changes) = diff(correction.before, correction.after)
                if await card.ask(text, changes: changes, note: keptBlocks(correction.failures)) {
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target else { throw Failure("App changée : rien n'a été collé") }
                    write(correction.item, to: pasteboard)
                    try press("v")
                    // Electron apps read the pasteboard asynchronously after ⌘V.
                    try await Task.sleep(for: .milliseconds(600))
                } else {
                    outcome = "Ignoré"
                }
            }
        } catch {
            problem = error.localizedDescription
        }
        card.close()
        restore()
        if let problem { finish(problem) } else { report(outcome, beep: false) }
        statusItem.button?.image = icon(busy: false)
        busy = false
    }

    func keptBlocks(_ failures: Int) -> String? {
        failures > 0 ? "\(failures) bloc(s) laissé(s) tel quel : mise en forme non respectée" : nil
    }

    func finish(_ problem: String?) {
        report(problem ?? "Corrigé", beep: problem != nil)
        if let problem {
            hud.show(problem, busy: false)
            hud.hide(after: .seconds(2.5))
        } else {
            hud.hide()
        }
    }

    @objc func rewrite(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        serve(pasteboard, .rewrite, error)
    }

    @objc func proofread(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        serve(pasteboard, .proofread, error)
    }

    // A service must fill the pasteboard before returning, so the main run loop is spun until Claude answers.
    func serve(_ pasteboard: NSPasteboard, _ mode: Mode, _ error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard !busy else {
            error.pointee = "Une correction est déjà en cours"
            return
        }
        busy = true
        hud.show("Reformulation…", busy: true)
        let options = Options(model: Settings.model, effort: Settings.effort, mode: mode)
        serviceResult = nil
        Task {
            do {
                let correction = try await correct(pasteboard, options)
                write(correction.item, to: pasteboard)
                serviceResult = .success(correction.failures)
            } catch {
                serviceResult = .failure(error)
            }
        }
        while serviceResult == nil { RunLoop.current.run(mode: .default, before: .now + 0.05) }
        switch serviceResult {
        case .success(let failures):
            finish(keptBlocks(failures))
        case .failure(let failure):
            error.pointee = failure.localizedDescription as NSString
            finish(failure.localizedDescription)
        case nil:
            break
        }
        busy = false
    }
}
