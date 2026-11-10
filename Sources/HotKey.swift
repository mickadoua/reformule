import AppKit
import Carbon.HIToolbox
import IOKit.hidsystem

struct HotKey: Codable, Equatable {
    var keyCode: Int64
    var modifiers: UInt64
    var rightSides: UInt64

    static let `default` = HotKey(keyCode: Int64(kVK_ANSI_Slash), modifiers: CGEventFlags.maskCommand.rawValue, rightSides: UInt64(NX_DEVICERCMDKEYMASK))
    static let modifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
    static let symbols: [(flag: CGEventFlags, right: Int32, symbol: String)] = [
        (.maskControl, NX_DEVICERCTLKEYMASK, "⌃"), (.maskAlternate, NX_DEVICERALTKEYMASK, "⌥"),
        (.maskShift, NX_DEVICERSHIFTKEYMASK, "⇧"), (.maskCommand, NX_DEVICERCMDKEYMASK, "⌘"),
    ]

    init(keyCode: Int64, modifiers: UInt64, rightSides: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.rightSides = rightSides
    }

    init(_ event: CGEvent) {
        keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        modifiers = event.flags.intersection(Self.modifierMask).rawValue
        rightSides = Self.symbols.map { UInt64($0.right) }.reduce(0) { $0 | (event.flags.rawValue & $1) }
    }

    func matches(_ event: CGEvent) -> Bool {
        let pressed = HotKey(event)
        return pressed.keyCode == keyCode && pressed.modifiers == modifiers && pressed.rightSides & rightSides == rightSides
    }

    var label: String {
        let flags = CGEventFlags(rawValue: modifiers)
        let parts = Self.symbols.filter { flags.contains($0.flag) }.map { $0.symbol + (rightSides & UInt64($0.right) != 0 ? " droit" : "") }
        return (parts + [keyName(CGKeyCode(keyCode))]).joined(separator: " + ")
    }

    var problem: String? {
        if CGEventFlags(rawValue: modifiers).isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate]) {
            return "Le raccourci doit contenir ⌘, ⌃ ou ⌥"
        }
        if modifiers == CGEventFlags.maskCommand.rawValue, "acvq".contains(where: { virtualKey(for: $0) == CGKeyCode(keyCode) }) {
            return "⌘A, ⌘C, ⌘V et ⌘Q sont réservés"
        }
        return nil
    }
}

func translate(_ code: CGKeyCode, modifiers: UInt32) -> String? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    return data.withUnsafeBytes { bytes -> String? in
        guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                       OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, chars.count, &length, &chars)
        return length > 0 ? String(utf16CodeUnits: chars, count: length) : nil
    }
}

func keyName(_ code: CGKeyCode) -> String {
    let names = [kVK_Space: "Espace", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦"]
    if let name = names[Int(code)] { return name }
    guard let text = translate(code, modifiers: 0), text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
        return "touche \(code)"
    }
    return text.uppercased()
}

// Keycodes are positional: on AZERTY the QWERTY "A" key is Q, so ⌘A would send ⌘Q.
func virtualKey(for character: Character) -> CGKeyCode? {
    (0..<128).map { CGKeyCode($0) }.first { translate($0, modifiers: UInt32(cmdKey >> 8) & 0xFF) == String(character) }
}

func press(_ character: Character) throws {
    guard let code = virtualKey(for: character) else { throw Failure("Touche « \(character) » introuvable sur cette disposition clavier") }
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = .maskCommand
        event?.post(tap: .cghidEventTap)
    }
}

func waitForModifiersRelease() async throws {
    for _ in 0..<75 {
        if CGEventSource.flagsState(.combinedSessionState).isDisjoint(with: HotKey.modifierMask) { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw Failure("Raccourci encore enfoncé")
}

func copied(_ pasteboard: NSPasteboard, since count: Int, within attempts: Int) async throws -> Bool {
    for _ in 0..<attempts {
        if pasteboard.changeCount != count { return true }
        try await Task.sleep(for: .milliseconds(20))
    }
    return false
}

nonisolated(unsafe) var keyTap: CFMachPort?

func onKeyDown(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // macOS disables a tap whose callback was too slow, e.g. while the main thread imports HTML.
    if type == .tapDisabledByTimeout, let keyTap { CGEvent.tapEnable(tap: keyTap, enable: true) }
    guard type == .keyDown, event.getIntegerValueField(.eventSourceUnixProcessID) != Int64(getpid()) else {
        return Unmanaged.passUnretained(event)
    }
    let consumed = MainActor.assumeIsolated { app.handle(event) }
    return consumed ? nil : Unmanaged.passUnretained(event)
}

func installKeyTap() -> Bool {
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                      eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback: onKeyDown, userInfo: nil) else { return false }
    keyTap = tap
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    return true
}
