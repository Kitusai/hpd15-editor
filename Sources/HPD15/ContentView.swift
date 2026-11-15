import SwiftUI
import HPD15Core

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    @State private var showConnection = false
    @State private var showJournal = false
    /// Changer de langue reconstruit toute l'interface.
    @AppStorage(AppLanguage.key) private var appLanguage = "auto"

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.stroke)
            Group {
                switch m.screen {
                case .set: SetView()
                case .effects: EffectsView()
                case .library: LibraryView(library: m.library)
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .id(appLanguage)
        .background(Theme.bg)
        .background(WindowAccessor())
        .overlay(alignment: .top) {
            if !m.progress.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.6)
                    Text(m.progress).font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 10)
            }
        }
        .alert(L("Erreur"), isPresented: Binding(get: { m.errorMessage != nil }, set: { if !$0 { m.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(m.errorMessage ?? "")
        }
        .alert(L("Information"), isPresented: Binding(get: { m.notice != nil }, set: { if !$0 { m.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(m.notice ?? "")
        }
        .sheet(isPresented: $showJournal) { JournalView(journal: m.journal).environmentObject(m) }
        .alert(L("Le HPD-15 a changé de patch"),
               isPresented: Binding(get: { m.devicePatchChange != nil }, set: { if !$0 { m.devicePatchChange = nil } })) {
            Button(L("Renvoyer mon set")) {
                m.devicePatchChange = nil
                m.resendCurrentSet()
            }
            Button(Lf("Lire %@", m.devicePatchChange ?? ""), role: .destructive) {
                if let c = m.devicePatchChange { m.readDevicePatch(c) }
            }
        } message: {
            Text(Lf("L'appareil est passé sur %@. Le set « %@ » affiché ici a des modifications non enregistrées : il n'est plus sur le HPD-15. Renvoyez-le pour continuer à l'éditer (puis enregistrez-le), ou lisez le nouveau patch (les modifications seront perdues).", m.devicePatchChange ?? "?", m.image.name ?? "?"))
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fingers.spread").foregroundColor(Theme.accent)
                Text("HPD-15").font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .padding(.bottom, 18)

            ForEach(Screen.allCases) { s in
                Button { m.screen = s } label: {
                    HStack(spacing: 10) {
                        Image(systemName: s.icon).frame(width: 20)
                        Text(L(s.rawValue))
                        Spacer()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(m.screen == s ? .white : Theme.dim)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(m.screen == s ? Color.white.opacity(0.10) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button { showJournal = true } label: {
                Label(L("Journal MIDI (diagnostic)"), systemImage: "doc.plaintext").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundColor(Theme.dim.opacity(0.8))
            .padding(.bottom, 6)

            Button { showConnection.toggle() } label: {
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(statusText).font(.system(size: 12, weight: .semibold))
                        Text(m.padChannel.map { Lf("Pads : canal %d", $0) } ?? L("Canal des pads inconnu"))
                            .font(.system(size: 11)).foregroundColor(Theme.dim)
                    }
                    Spacer()
                    Image(systemName: "gearshape").foregroundColor(Theme.dim)
                }
                .padding(10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showConnection, arrowEdge: .trailing) {
                ConnectionView().environmentObject(m)
            }
        }
        .padding(14)
        .frame(width: 210)
        .background(Theme.panel)
    }

    private var statusColor: Color {
        if !m.connected { return Theme.danger }
        return m.deviceFound ? Theme.ok : Theme.accent
    }

    private var statusText: String {
        if !m.connected { return L("Non connecté") }
        return m.deviceFound ? L("HPD-15 connecté") : L("HPD-15 non trouvé")
    }
}

struct PlaceholderView: View {
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hammer").font(.system(size: 34)).foregroundColor(Theme.dim)
            Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(text).foregroundColor(Theme.dim).multilineTextAlignment(.center).frame(maxWidth: 380)
        }
    }
}

struct ConnectionView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Connexion MIDI")).font(.headline)
            Picker(L("Entrée"), selection: $m.selectedSource) {
                Text("—").tag(MIDIEndpointRefZero)
                ForEach(m.sources) { Text($0.name).tag($0.ref) }
            }
            Picker(L("Sortie"), selection: $m.selectedDestination) {
                Text("—").tag(MIDIEndpointRefZero)
                ForEach(m.destinations) { Text($0.name).tag($0.ref) }
            }
            Picker("Device ID", selection: $m.deviceNumber) {
                ForEach(1...32, id: \.self) { Text("\($0)").tag($0) }
            }
            Text(L("Le HPD-15 est relié par ses prises MIDI à l'interface UM-ONE. Device ID d'usine : 17."))
                .font(.system(size: 11)).foregroundColor(Theme.dim)
            HStack {
                Button(L("Actualiser")) { m.refreshPorts() }
                Button(L("Connecter et lire")) { m.connect(); m.deviceFound = false; m.readFromDevice() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}

/// Valeur « aucun port » typée pour les sélecteurs.
let MIDIEndpointRefZero: UInt32 = 0

struct JournalView: View {
    @ObservedObject var journal: JournalStore
    @EnvironmentObject var m: AppModel
    @Environment(\.presentationMode) private var presentation

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("Journal MIDI")).font(.headline)
                Spacer()
                Button(L("Copier")) { m.copyLog() }
                Button(L("Effacer")) { m.clearLog() }
                Button(L("Fermer")) { presentation.wrappedValue.dismiss() }
            }
            .padding(12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(journal.lines) { line in
                            Text(line.plain)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(color(line.direction))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: journal.lines.count) { _ in
                    if let last = journal.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .frame(width: 900, height: 520)
    }

    private func color(_ d: HPDLogEntry.Direction) -> Color {
        switch d {
        case .tx: return Theme.blue
        case .rx: return Theme.ok
        case .info: return Theme.dim
        case .error: return Theme.danger
        }
    }
}
