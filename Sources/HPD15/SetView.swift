import SwiftUI
import HPD15Core

/// Écran principal : le HPD-15 à gauche, le pad sélectionné et la liste des sons à droite.
struct SetView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(spacing: 12) {
            SetHeader()
            if m.image.bytes.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 12) {
                    SurfaceView()
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                        .card()
                    VStack(spacing: 12) {
                        ZoneInspector()
                        SoundBrowser()
                    }
                    .frame(width: 400)
                }
            }
        }
        .padding(14)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.grid.cross").font(.system(size: 40)).foregroundColor(Theme.dim)
            Text(m.connected ? L("Aucun set lu pour l'instant") : L("HPD-15 non connecté"))
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(L("Choisissez l'entrée et la sortie « UM-ONE » (en bas à gauche), puis lisez le set en cours ou chargez un patch."))
                .foregroundColor(Theme.dim).multilineTextAlignment(.center).frame(maxWidth: 420)
            Button(L("Lire le set en cours du HPD-15")) { m.readFromDevice() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!m.connected || m.busy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - En-tête du set

struct SetHeader: View {
    @EnvironmentObject var m: AppModel
    @State private var name = ""
    @State private var showSaveAs = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(L("SET")).font(.system(size: 10, weight: .bold)).foregroundColor(Theme.dim)
                    TextField(L("Nom (10 caractères)"), text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .frame(width: 160)
                        .onChange(of: name) { v in
                            let clean = String(v.unicodeScalars.filter { $0.value >= 32 && $0.value <= 126 }.prefix(10).map { Character($0) })
                            if clean != v { name = clean }
                        }
                        .onSubmit { m.setName(name) }
                        .disabled(m.image.bytes.isEmpty)
                        .help(L("Nom du set sur le HPD-15 (validez avec Entrée)."))
                }
                HStack(spacing: 6) {
                    Chip(text: m.origin.isEmpty ? "—" : m.origin)
                    if m.dirty { Chip(text: L("modifié"), color: Theme.accent.opacity(0.25), textColor: Theme.accent) }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(Lf("VOLUME DU SET  %d", m.masterVolume)).font(.system(size: 10, weight: .bold)).foregroundColor(Theme.dim)
                HSlider(value: m.masterVolume, range: 0...127, defaultValue: 100) { m.setMasterVolume($0) }
                    .frame(width: 130)
                    .disabled(m.image.bytes.isEmpty)
            }

            PatchMenu()

            Button { m.save() } label: { Label(L("Enregistrer"), systemImage: "square.and.arrow.down.on.square") }
                .buttonStyle(SoftButtonStyle())
                .disabled(m.loadedEntry == nil || !m.image.isComplete || m.busy)
                .keyboardShortcut("s", modifiers: .command)
                .help(m.loadedEntry.map { Lf("Écrase « %@ » avec le set en cours (⌘S).", $0.item.name) } ?? L("Aucun fichier chargé : utilisez « Enregistrer sous… »."))
            Button { showSaveAs = true } label: { Label(L("Enregistrer sous…"), systemImage: "doc.badge.plus") }
                .buttonStyle(SoftButtonStyle())
                .disabled(!m.image.isComplete || m.busy)
                .keyboardShortcut("s", modifiers: [.command, .shift])

            Button { m.readFromDevice() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(SoftButtonStyle())
                .disabled(!m.connected || m.busy)
                .help(L("Relire le HPD-15 : reprend le set en cours sur l'appareil (y compris les réglages faits sur l'appareil lui-même)."))
        }
        .card()
        .sheet(isPresented: $showSaveAs) { SaveAsSheet().environmentObject(m) }
        .onAppear { name = m.image.name ?? "" }
        .onChange(of: m.image.name) { n in if let n = n, n != name { name = n } }
    }
}

/// Menu de chargement des presets d'usine et des mémoires User.
struct PatchMenu: View {
    @EnvironmentObject var m: AppModel
    @State private var pendingCode: String?

    private func load(_ code: String) {
        if m.dirty { pendingCode = code } else { m.loadPatch(code: code) }
    }

    var body: some View {
        Menu {
            if let cat = m.catalog {
                Section(L("Presets d'usine")) {
                    ForEach(cat.presetGroups, id: \.id) { g in
                        Menu("\(String(format: "%02d", g.id)) · \(g.name)") {
                            ForEach(g.patches) { p in
                                Button("\(p.code)  \(p.name)") { load(p.code) }
                            }
                        }
                    }
                }
                Section(L("Mémoires User")) {
                    ForEach(1...10, id: \.self) { g in
                        Menu(Lf("Groupe U%02d", g)) {
                            ForEach(1...8, id: \.self) { i in
                                let code = "U\(String(format: "%02d%02d", g, i))"
                                Button(code) { load(code) }
                            }
                        }
                    }
                }
            }
        } label: {
            Label(L("Charger"), systemImage: "square.and.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .disabled(!m.connected || m.busy)
        .help(L("Sélectionne le patch sur le HPD-15 puis le lit : il devient la base du set."))
        .alert(L("Remplacer le set en cours ?"), isPresented: Binding(get: { pendingCode != nil }, set: { if !$0 { pendingCode = nil } })) {
            Button(L("Annuler"), role: .cancel) { pendingCode = nil }
            Button(Lf("Charger %@", pendingCode ?? ""), role: .destructive) {
                if let c = pendingCode { m.loadPatch(code: c) }
                pendingCode = nil
            }
        } message: {
            Text(L("Le set en cours a des modifications non enregistrées. Elles seront perdues."))
        }
    }
}

// MARK: - Inspecteur du pad sélectionné

struct ZoneInspector: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject private var palette = Palette.shared

    var body: some View {
        let z = m.selectedZone
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title(z)).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundColor(Theme.accent)
                Spacer()
                Button { m.audition(z) } label: { Label(L("Écouter"), systemImage: "play.fill") }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(m.padChannel == nil)
                    .help(L("Fait sonner ce pad sur le HPD-15 (ou cliquez à nouveau sur le pad)."))
            }
            if let s = m.zoneState(z) {
                let inst = m.instrument(s.inst)
                HStack(spacing: 8) {
                    Text(inst?.code ?? "—").font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.category(inst?.category))
                    Text(inst?.name ?? Lf("Son %d", s.inst)).font(.system(size: 15, weight: .semibold))
                    if let c = inst?.category { Chip(text: Theme.categoryLabel(c)) }
                    Spacer()
                }
                Divider().overlay(Theme.stroke)
                ParamSlider(label: L("Niveau"), value: s.level, range: 0...127, defaultValue: 100) { m.setParam(.level, $0, for: z) }
                PitchRow(cents: s.pitchCents) { m.setParam(.pitch, $0, for: z) }
                PanRow(pan: s.pan) { m.setParam(.pan, $0, for: z) }
                ParamSlider(label: L("Durée (decay)"), value: s.decay, range: -31...31, defaultValue: 0, signed: true) { m.setParam(.decay, $0, for: z) }
                ParamSlider(label: L("Balayage (sweep)"), value: s.sweep, range: -31...31, defaultValue: 0, signed: true) { m.setParam(.sweep, $0, for: z) }
                ParamSlider(label: L("Couleur"), value: s.color, range: -31...31, defaultValue: 0, signed: true) { m.setParam(.color, $0, for: z) }
                ParamSlider(label: L("Envoi réverbération"), value: s.reverbSend, range: 0...127, defaultValue: 40) { m.setParam(.reverb, $0, for: z) }
                if let t = m.reverbType, PatchMap.reverbIsOff(t) {
                    Label(L("La réverbération du set est sur OFF : l'envoi n'a pas d'effet (choisissez-la dans « Effets du set »)."),
                          systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10)).foregroundColor(Theme.accent)
                }
                Toggle(isOn: Binding(get: { s.mfx }, set: { m.setParam(.mfx, $0 ? 1 : 0, for: z) })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Ce pad passe par le multi-effet")).font(.system(size: 12, weight: .medium))
                        Text(m.multiEffectsOn
                             ? L("Le type de multi-effet est commun à tout le set (écran « Effets du set »).")
                             : L("Multi-effet du set désactivé : à activer dans « Effets du set »."))
                            .font(.system(size: 10)).foregroundColor(m.multiEffectsOn ? Theme.dim : Theme.accent)
                    }
                }
                .toggleStyle(.switch)
            } else {
                Text(L("Zone non lue.")).foregroundColor(Theme.dim)
            }
        }
        .card()
        .disabled(m.busy)
    }

    private func title(_ z: Zone) -> String {
        switch z {
        case .ribbonL: return L("Ruban gauche")
        case .ribbonR: return L("Ruban droit")
        case .dBeam: return "D Beam"
        case .pedal: return L("Pédale")
        case .trig1: return "Trig 1"
        case .trig2: return "Trig 2"
        default: return Lf("Pad %@", z.rawValue)
        }
    }
}

/// Curseur horizontal avec valeur et remise à la valeur par défaut.
struct ParamSlider: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    var defaultValue: Int = 0
    var signed = false
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12)).frame(width: 128, alignment: .leading)
                .onTapGesture(count: 2) { onChange(defaultValue) }
            HSlider(value: value, range: range, defaultValue: defaultValue, origin: signed ? 0 : nil, onChange: onChange)
            Text(signed && value > 0 ? "+\(value)" : "\(value)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 38, alignment: .trailing)
            Button { onChange(defaultValue) } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.plain).foregroundColor(Theme.dim)
                .help(Lf("Valeur par défaut (%d)", defaultValue))
        }
    }
}

/// Accord : curseur par demi-tons, réglage fin par 5 cents.
struct PitchRow: View {
    let cents: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(L("Accord")).font(.system(size: 12)).frame(width: 128, alignment: .leading)
            HSlider(value: cents, range: -2400...2400, defaultValue: 0, step: 100, origin: 0, onChange: onChange)
            Stepper("", onIncrement: { onChange(min(2400, cents + 5)) }, onDecrement: { onChange(max(-2400, cents - 5)) })
                .labelsHidden()
            Text(text).font(.system(size: 12, weight: .semibold, design: .monospaced)).frame(width: 62, alignment: .trailing)
            Button { onChange(0) } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.plain).foregroundColor(Theme.dim).help(L("0 cent"))
        }
    }

    private var text: String {
        let semis = Double(cents) / 100
        if cents % 100 == 0 { return String(format: L("%+.0f dt"), semis) }
        return "\(cents > 0 ? "+" : "")\(cents) c"
    }
}

/// Panoramique : fixe (L63…R63), aléatoire ou alterné.
struct PanRow: View {
    let pan: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(L("Panoramique")).font(.system(size: 12)).frame(width: 128, alignment: .leading)
            HSlider(value: min(127, max(1, pan)), range: 1...127, defaultValue: 64, origin: 64, disabled: pan > 127, onChange: onChange)
            Menu(label) {
                Button(L("Fixe (centre)")) { onChange(64) }
                Button(L("Aléatoire")) { onChange(128) }
                Button(L("Alterné G/D")) { onChange(129) }
            }
            .menuStyle(.borderlessButton)
            .frame(width: 64)
        }
    }

    private var label: String {
        switch pan {
        case 64: return "C"
        case 1..<64: return Lf("G%d", 64 - pan)
        case 65...127: return Lf("D%d", pan - 64)
        case 128: return L("Aléa.")
        default: return L("Alt.")
        }
    }
}

// MARK: - Liste des sons

struct SoundBrowser: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject private var palette = Palette.shared
    @State private var search = ""
    @State private var family: String?
    @AppStorage("auditionOnPick") private var auditionOnPick = true

    var body: some View {
        let z = m.selectedZone
        let current = m.zoneState(z)?.inst
        let list = filtered
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("SONS")).font(.system(size: 10, weight: .bold)).foregroundColor(Theme.dim)
                Text(Lf("— un clic remplace le son de %@", z.rawValue)).font(.system(size: 10)).foregroundColor(Theme.dim)
                Spacer()
                Toggle(L("Écouter"), isOn: $auditionOnPick).toggleStyle(.checkbox).font(.system(size: 11))
            }
            TextField(L("Rechercher parmi les 601 sons (nom ou code, ex. « conga », « L11 »)"), text: $search)
                .textFieldStyle(.roundedBorder)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    FilterChip(label: L("Tous"), on: family == nil) { family = nil }
                    ForEach(m.catalog?.categories ?? [], id: \.self) { c in
                        FilterChip(label: Theme.categoryLabel(c), on: family == c, color: Theme.category(c)) {
                            family = (family == c) ? nil : c
                        }
                    }
                }
            }
            ScrollViewReader { proxy in
                List {
                    ForEach(list) { i in
                        SoundRow(inst: i, current: i.value == current)
                            .id(i.value)
                            .contentShape(Rectangle())
                            .onTapGesture { pick(i, for: z) }
                    }
                }
                .listStyle(.plain)
                .onAppear { if let c = current { proxy.scrollTo(c, anchor: .center) } }
                .onChange(of: m.selectedZone) { _ in
                    if let c = m.zoneState(m.selectedZone)?.inst { proxy.scrollTo(c, anchor: .center) }
                }
            }
            Text(Lf("%d sons", list.count)).font(.system(size: 10)).foregroundColor(Theme.dim)
        }
        .card()
        .frame(maxHeight: .infinity)
        .disabled(m.busy || m.image.bytes.isEmpty)
    }

    private var filtered: [HPD15Catalog.Instrument] {
        let all = m.catalog?.instruments ?? []
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { i in
            (family == nil || i.category == family) &&
            (q.isEmpty || i.name.lowercased().contains(q) || i.code.lowercased() == q || i.code.lowercased().hasPrefix(q))
        }
    }

    private func pick(_ i: HPD15Catalog.Instrument, for z: Zone) {
        m.setInstrument(i.value, for: z)
        if auditionOnPick {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                m.audition(z)
            }
        }
    }
}

struct SoundRow: View, Equatable {
    let inst: HPD15Catalog.Instrument
    let current: Bool

    static func == (a: SoundRow, b: SoundRow) -> Bool { a.inst.value == b.inst.value && a.current == b.current }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.category(inst.category)).frame(width: 7, height: 7)
            Text(inst.code).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(Theme.dim)
                .frame(width: 34, alignment: .leading)
            Text(inst.name).font(.system(size: 13, weight: current ? .bold : .regular))
            Spacer()
            if current { Image(systemName: "checkmark").foregroundColor(Theme.accent) }
        }
        .padding(.vertical, 2)
        .foregroundColor(current ? Theme.accent : .white)
    }
}
