import AppKit
import SwiftUI

func diff(_ before: String, _ after: String) -> (text: AttributedString, changes: Int) {
    let words = { (text: String) in text.matches(of: #/\w+|\s+|[^\w\s]/#).map { String($0.output) } }
    let old = words(before), new = words(after)
    var removed = Set<Int>(), inserted = Set<Int>()
    for change in new.difference(from: old) {
        switch change {
        case .remove(let offset, _, _): removed.insert(offset)
        case .insert(let offset, _, _): inserted.insert(offset)
        }
    }
    var text = AttributedString()
    var changes = 0, changing = false, afterRemoval = false, i = 0, j = 0
    while i < old.count || j < new.count {
        var part: AttributedString
        if i < old.count, removed.contains(i) {
            part = AttributedString(old[i])
            part.swiftUI.strikethroughStyle = .single
            part.swiftUI.foregroundColor = .red
            i += 1
        } else if j < new.count, inserted.contains(j) {
            part = AttributedString(new[j])
            part.swiftUI.foregroundColor = .green
            part.swiftUI.backgroundColor = .green.opacity(0.15)
            if afterRemoval { text.append(AttributedString(" ")) }
            j += 1
        } else if i < old.count, j < new.count {
            text.append(AttributedString(new[j]))
            changing = false
            afterRemoval = false
            i += 1
            j += 1
            continue
        } else {
            break
        }
        if !changing { changes += 1 }
        changing = true
        afterRemoval = part.swiftUI.strikethroughStyle != nil
        text.append(part)
    }
    return (text, changes)
}

@MainActor final class SuggestionModel: ObservableObject {
    enum Phase { case loading, ready(text: AttributedString, changes: Int, height: CGFloat, note: String?) }

    @Published var phase = Phase.loading
    var decide: @MainActor (Bool) -> Void = { _ in }
}

struct SuggestionView: View {
    static let width: CGFloat = 400
    static let font = NSFont.systemFont(ofSize: 13.5)

    @ObservedObject var model: SuggestionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Tile(symbol: "pencil.and.scribble", color: .indigo, size: 20)
                Text("Reformule").font(.headline)
                Spacer()
                if case .ready(_, let changes, _, _) = model.phase {
                    Text(changes == 1 ? "1 modification" : "\(changes) modifications").font(.caption).foregroundStyle(.secondary)
                }
            }
            switch model.phase {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reformulation…").foregroundStyle(.secondary)
                }
            case .ready(let text, _, let height, let note):
                ScrollView {
                    Text(text).font(Font(Self.font)).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(height, 260))
                if let note {
                    Label(note, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button { model.decide(false) } label: { Text("Ignorer  ⎋").padding(.horizontal, 4) }
                        .buttonStyle(.bordered)
                    Button { model.decide(true) } label: { Text("Remplacer  ⏎").padding(.horizontal, 4) }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                }
                .controlSize(.large)
            }
        }
        .padding(16)
        .frame(width: Self.width)
        .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
    }
}

// The card must never take keyboard focus from the app whose text it corrects.
final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

// A non-key window swallows the first click unless the view accepts it.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class SuggestionCard {
    let model = SuggestionModel()
    let panel = CardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    var anchor = NSRect.zero
    var cancelled = false
    var continuation: CheckedContinuation<Bool, Never>?
    var mouseMonitor: Any?
    var appObserver: NSObjectProtocol?

    var isOpen: Bool { panel.isVisible }
    var isReady: Bool {
        if case .ready = model.phase { return true }
        return false
    }

    init() {
        panel.contentView = FirstMouseHostingView(rootView: SuggestionView(model: model))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        model.decide = { [unowned self] in resolve($0) }
    }

    func show(at anchor: NSRect) {
        self.anchor = anchor
        cancelled = false
        model.phase = .loading
        place()
        panel.orderFrontRegardless()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { self.dismiss() }
        }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.dismiss() }
        }
    }

    func ask(_ text: AttributedString, changes: Int, note: String?) async -> Bool {
        let height = NSAttributedString(string: String(text.characters), attributes: [.font: SuggestionView.font, .paragraphStyle: {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            return style
        }()]).boundingRect(with: NSSize(width: SuggestionView.width - 32, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).height
        model.phase = .ready(text: text, changes: changes, height: ceil(height) + 4, note: note)
        place()
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve(_ accepted: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        close()
        continuation.resume(returning: accepted)
    }

    func dismiss() {
        if continuation != nil { return resolve(false) }
        cancelled = true
        close()
    }

    func close() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        mouseMonitor = nil
        appObserver = nil
        panel.orderOut(nil)
    }

    func place() {
        guard let view = panel.contentView else { return }
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor.insetBy(dx: -1, dy: -1)) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - 8 - size.height)
        if origin.y < visible.minY { origin.y = anchor.maxY + 8 }
        origin.y = max(visible.minY + 8, min(origin.y, visible.maxY - size.height - 8))
        origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - size.width - 8))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.invalidateShadow()
    }
}

// Text bounds come from Accessibility when the app exposes them, otherwise the card follows the pointer.
func selectionAnchor() -> NSRect {
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.25)
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let toCocoa = { (rect: CGRect) in NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height) }
    var focused: CFTypeRef?
    if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
       let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
        let element = focused as! AXUIElement
        var range: CFTypeRef?, bounds: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success, let range,
           AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
           let rect = axValue(bounds, .cgRect, CGRect.zero), rect.width > 1 || rect.height > 1 {
            return toCocoa(rect)
        }
        var position: CFTypeRef?, size: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
           AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
           let origin = axValue(position, .cgPoint, CGPoint.zero), let extent = axValue(size, .cgSize, CGSize.zero),
           extent.width > 1, extent.height > 1 {
            return toCocoa(CGRect(origin: origin, size: extent))
        }
    }
    return NSRect(origin: NSEvent.mouseLocation, size: .zero)
}

func axValue<T: BitwiseCopyable>(_ value: CFTypeRef?, _ type: AXValueType, _ initial: T) -> T? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var result = initial
    return AXValueGetValue(value as! AXValue, type, &result) ? result : nil
}
