import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class ActionItem: NSMenuItem {
    let handler: () -> Void

    init(_ title: String, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc func fire() { handler() }
}

@MainActor final class App: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let hud = Hud()
    var hotKey = Settings.hotKey
    var status = "Prêt"
    var busy = false
    var recording: Task<Void, Never>?
    var serviceResult: Result<Int, any Error>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "✎"
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

    func buildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(choice("Modèle", Settings.model, \.label) { Settings.model = $0 })
        menu.addItem(choice("Effort", Settings.effort, \.label) { Settings.effort = $0 })
        menu.addItem(choice("Mode", Settings.mode, \.label) { Settings.mode = $0 })
        menu.addItem(ActionItem("Raccourci : \(hotKey.label)…") { self.startRecording() })
        menu.addItem(ActionItem("Lancer à l'ouverture de session", checked: SMAppService.mainApp.status == .enabled) { self.toggleLogin() })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter Reformule", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func choice<T: CaseIterable & Equatable>(_ title: String, _ current: T, _ label: (T) -> String, set: @escaping (T) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: "\(title) : \(label(current))", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for value in T.allCases {
            submenu.addItem(ActionItem(label(value), checked: value == current) {
                set(value)
                self.buildMenu()
            })
        }
        item.submenu = submenu
        return item
    }

    func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            report(error.localizedDescription)
        }
        buildMenu()
    }

    func report(_ message: String, beep: Bool = true) {
        status = message
        if beep { NSSound.beep() }
        buildMenu()
    }

    func startRecording() {
        guard keyTap != nil else { return report("Autoriser d'abord Reformule dans Accessibilité") }
        hud.show("Tape le nouveau raccourci (Échap pour annuler)", busy: false)
        recording = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            finishRecording(nil)
        }
    }

    func finishRecording(_ key: HotKey?) {
        recording?.cancel()
        recording = nil
        if let key {
            hotKey = key
            Settings.hotKey = key
            hud.show("Raccourci : \(key.label)", busy: false)
            hud.hide(after: .seconds(1.5))
        } else {
            hud.hide()
        }
        buildMenu()
    }

    func handle(_ event: CGEvent) -> Bool {
        if recording != nil {
            let key = HotKey(event)
            if key.keyCode == Int64(kVK_Escape) {
                finishRecording(nil)
            } else if let problem = key.problem {
                hud.show(problem, busy: false)
            } else {
                finishRecording(key)
            }
            return true
        }
        guard hotKey.matches(event) else { return false }
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { Task { await run() } }
        return true
    }

    func run() async {
        guard !busy else { return }
        guard AXIsProcessTrusted() else { return report("Autoriser Reformule dans Réglages > Confidentialité et sécurité > Accessibilité") }
        busy = true
        statusItem.button?.title = "…"
        hud.show("Reformulation…", busy: true)
        let pasteboard = NSPasteboard.general
        let saved: [NSPasteboardItem] = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        let target = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var keepResult = false
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
            let failures = try await rewritePasteboard(pasteboard, Settings.options)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target else {
                keepResult = true
                throw Failure("App changée pendant la correction : le résultat est dans le presse-papiers")
            }
            try press("v")
            // Electron apps read the pasteboard asynchronously after ⌘V.
            try await Task.sleep(for: .milliseconds(600))
            problem = keptBlocks(failures)
        } catch {
            problem = error.localizedDescription
        }
        finish(problem)
        if !keepResult {
            pasteboard.clearContents()
            pasteboard.writeObjects(saved)
        }
        statusItem.button?.title = "✎"
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
            do { serviceResult = .success(try await rewritePasteboard(pasteboard, options)) } catch { serviceResult = .failure(error) }
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
