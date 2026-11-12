import Combine
import ServiceManagement
import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case general, correction, shortcuts, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "Général"
        case .correction: "Correction"
        case .shortcuts: "Raccourcis"
        case .about: "À propos"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .correction: "wand.and.sparkles"
        case .shortcuts: "keyboard.fill"
        case .about: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .correction: .indigo
        case .shortcuts: .purple
        case .about: .blue
        }
    }
}

// @State is a macro in this SDK and the Command Line Tools ship without its plugin.
final class Box<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

struct Tile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct SettingsView: View {
    @ObservedObject var app: App
    @StateObject private var pane = Box<Pane?>(.general)

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane.value) { pane in
                Label { Text(pane.title) } icon: { Tile(symbol: pane.symbol, color: pane.color) }
            }
            .navigationSplitViewColumnWidth(200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch pane.value ?? .general {
                case .general: GeneralPane(app: app)
                case .correction: CorrectionPane()
                case .shortcuts: ShortcutsPane(app: app)
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((pane.value ?? .general).title)
        }
    }
}

struct GeneralPane: View {
    @ObservedObject var app: App
    @StateObject private var launchAtLogin = Box(SMAppService.mainApp.status == .enabled)
    @StateObject private var trusted = Box(AXIsProcessTrusted())

    var body: some View {
        Form {
            Section("Système") {
                Toggle("Ouvrir à l'ouverture de session", isOn: Binding(get: { launchAtLogin.value }, set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        app.report(error.localizedDescription)
                    }
                    launchAtLogin.value = SMAppService.mainApp.status == .enabled
                }))
            }
            Section("Autorisation") {
                LabeledContent {
                    if trusted.value {
                        Label("Autorisée", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Autoriser…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                } label: {
                    Text("Accessibilité")
                    Text("Nécessaire au raccourci clavier, pas au clic droit")
                }
            }
            Section("Activité") {
                LabeledContent("Dernière correction", value: app.status)
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in trusted.value = AXIsProcessTrusted() }
    }
}

struct CorrectionPane: View {
    @AppStorage("model") private var model: Model = .opus
    @AppStorage("effort") private var effort: Effort = .low
    @AppStorage("mode") private var mode: Mode = .rewrite

    var body: some View {
        Form {
            Section("Modèle") {
                Picker(selection: $model) {
                    ForEach(Model.allCases, id: \.self) { Text($0.label) }
                } label: {
                    Text("Modèle")
                    Text("Dernière version de chaque modèle, via Claude Code")
                }
                Picker(selection: $effort) {
                    ForEach(Effort.allCases, id: \.self) { Text($0.label) }
                } label: {
                    Text("Effort")
                    Text("Plus d'effort, plus de réflexion et d'attente")
                }
                .pickerStyle(.segmented)
            }
            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { mode in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.label)
                            Text(mode.summary).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            } header: {
                Text("Mode")
            } footer: {
                Text("Le raccourci clavier applique ce mode. Le clic droit propose les deux.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct ShortcutsPane: View {
    @ObservedObject var app: App

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button {
                        if app.recording { app.stopRecording() } else { app.startRecording() }
                    } label: {
                        Text(app.recording ? "Tape le raccourci…" : app.hotKey.label).frame(minWidth: 130)
                    }
                    .buttonStyle(.bordered)
                    .tint(app.recording ? .accentColor : nil)
                } label: {
                    Text("Corriger le champ actif")
                    if let problem = app.recordingProblem {
                        Text(problem).foregroundStyle(.red)
                    } else {
                        Text("La sélection, ou tout le champ s'il n'y en a pas")
                    }
                }
            } header: {
                Text("Raccourci clavier")
            } footer: {
                Text("Clique, puis tape la combinaison : elle doit contenir ⌘, ⌃ ou ⌥, et Échap annule. Les touches de gauche et de droite sont distinguées.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Reformule : corriger et reformuler", value: "Services")
                LabeledContent("Reformule : corriger seulement", value: "Services")
            } header: {
                Text("Clic droit")
            } footer: {
                Text("Sur une sélection, dans le sous-menu Services. Pour les activer ou leur donner un raccourci : Réglages Système > Clavier > Raccourcis clavier > Services > Texte.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct AboutPane: View {
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Tile(symbol: "pencil.and.scribble", color: .indigo, size: 64)
                    Text("Reformule").font(.title2.bold()).padding(.top, 4)
                    Text("Version \(version)").foregroundStyle(.secondary)
                    Text("Corrige et reformule le texte de n'importe quelle app, sans perdre la mise en forme.")
                        .multilineTextAlignment(.center).padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("Confidentialité") {
                Text("Le texte est envoyé à Anthropic par Claude Code, avec le compte connecté, et décompté sur son abonnement ou sa facturation.")
            }
            Section {
                Link("Code source", destination: URL(string: "https://github.com/mickadoua/reformule")!)
                LabeledContent("Licence", value: "MIT")
            }
        }
    }
}
