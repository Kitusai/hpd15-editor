import SwiftUI
import HPD15Core

/// Écran « Effets du set » : une réverbération et un multi-effet, communs à tout le set.
/// Chaque pad décide seulement s'il passe par le multi-effet et combien il envoie à la réverbération.
struct EffectsView: View {
    @EnvironmentObject var m: AppModel
    @State private var showRaw = false

    typealias E = PatchMap.EffectParam

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Effets du set")).font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(Lf("— réglages communs à tous les pads de « %@ »", m.image.name ?? "?"))
                        .font(.system(size: 13)).foregroundColor(Theme.dim)
                    Spacer()
                }
                if m.effectByte(0) == nil {
                    Text(L("Aucun set lu : lisez le HPD-15 ou chargez un patch depuis l'écran Set."))
                        .foregroundColor(Theme.dim).card()
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        reverbCard
                        mfxCard
                    }
                    padsCard
                }
            }
            .padding(14)
        }
        .disabled(m.busy)
    }

    // MARK: Réverbération

    private var reverbCard: some View {
        let type = m.effectByte(E.reverbType) ?? 0
        let off = PatchMap.reverbIsOff(type)
        return VStack(alignment: .leading, spacing: 10) {
            Label(L("Réverbération"), systemImage: "dot.radiowaves.left.and.right")
                .font(.system(size: 15, weight: .bold))
            HStack {
                Text(L("Type")).font(.system(size: 12)).frame(width: 128, alignment: .leading)
                Picker("", selection: Binding(get: { type }, set: { m.setEffect(E.reverbType, $0) })) {
                    if type == 0 { Text(L("OFF (valeur 0)")).tag(0) }
                    ForEach(1...PatchMap.reverbTypeNames.count, id: \.self) { v in
                        Text(v == 1 ? L("OFF (aucune réverbération)") : PatchMap.reverbTypeName(v)).tag(v)
                    }
                }
                .labelsHidden()
            }
            if off {
                Text(L("Réverbération coupée : les envois des pads n'ont aucun effet."))
                    .font(.system(size: 11)).foregroundColor(Theme.accent)
            }
            Group {
                ParamSlider(label: L("Niveau"), value: m.effectByte(E.reverbLevel) ?? 0, range: 0...127, defaultValue: 64) { m.setEffect(E.reverbLevel, $0) }
                ParamSlider(label: L("Durée"), value: m.effectByte(E.reverbTime) ?? 0, range: 0...127, defaultValue: 64) { m.setEffect(E.reverbTime, $0) }
                HStack {
                    Text(L("Atténuation des aigus")).font(.system(size: 12)).frame(width: 128, alignment: .leading)
                    Picker("", selection: Binding(get: { m.effectByte(E.reverbHFDamp) ?? 17 }, set: { m.setEffect(E.reverbHFDamp, $0) })) {
                        ForEach(Array(PatchMap.hfDampNames.enumerated()), id: \.offset) { i, n in Text(n).tag(i) }
                    }
                    .labelsHidden()
                }
                ParamSlider(label: L("Réinjection (délais)"), value: m.effectByte(E.delayFeedback) ?? 0, range: 0...127, defaultValue: 0) { m.setEffect(E.delayFeedback, $0) }
            }
            .disabled(off)
            .opacity(off ? 0.45 : 1)
            infoLine(L("Algorithme"), name(PatchMap.reverbAlgorithmNames, m.effectByte(E.reverbAlgorithm)))
        }
        .card()
        .frame(maxWidth: .infinity)
    }

    // MARK: Multi-effet

    private var mfxCard: some View {
        let type = m.effectByte(E.mfxType) ?? 0
        let on = m.multiEffectsOn
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("Multi-effet"), systemImage: "sparkles").font(.system(size: 15, weight: .bold))
                Spacer()
                Toggle(L("Actif"), isOn: Binding(get: { on }, set: { m.setMultiEffects($0) }))
                    .toggleStyle(.switch)
                    .help(L("Bouton [MULTI EFFECTS] du HPD-15, mémorisé dans le set."))
            }
            if !on {
                Text(L("Multi-effet désactivé : aucune zone ne l'entend, même celles qui « passent par le multi-effet »."))
                    .font(.system(size: 11)).foregroundColor(Theme.accent)
            }
            HStack {
                Text(L("Type")).font(.system(size: 12)).frame(width: 128, alignment: .leading)
                Picker("", selection: Binding(get: { type }, set: { m.setEffect(E.mfxType, $0) })) {
                    if type == 0 { Text(L("00  (valeur 0)")).tag(0) }
                    ForEach(1...PatchMap.mfxTypeNames.count, id: \.self) { v in
                        Text("\(String(format: "%02d", v))  \(PatchMap.mfxTypeName(v))").tag(v)
                    }
                }
                .labelsHidden()
            }
            Group {
                ParamSlider(label: L("Profondeur"), value: m.effectByte(E.mfxDepth) ?? 0, range: 0...127, defaultValue: 64) { m.setEffect(E.mfxDepth, $0) }
                ParamSlider(label: L("Volume de sortie"), value: m.effectByte(E.mfxOutput) ?? 0, range: 0...127, defaultValue: 127) { m.setEffect(E.mfxOutput, $0) }
                ParamSlider(label: L("Envoi vers réverb."), value: m.effectByte(E.mfxReverbSend) ?? 0, range: 0...127, defaultValue: 0) { m.setEffect(E.mfxReverbSend, $0) }
            }
            .opacity(on ? 1 : 0.6)
            infoLine(L("Algorithme"), name(PatchMap.mfxAlgorithmNames, m.effectByte(E.mfxAlgorithm)))
            DisclosureGroup(L("Paramètres détaillés (valeurs brutes, codage non vérifié)"), isExpanded: $showRaw) {
                let raw = (0..<12).map { m.effectByte(0x0C + $0) ?? 0 }
                HStack(spacing: 6) {
                    ForEach(0..<12, id: \.self) { i in
                        VStack(spacing: 2) {
                            Text("P\(i + 1)").font(.system(size: 9)).foregroundColor(Theme.dim)
                            Text("\(raw[i])").font(.system(size: 11, design: .monospaced))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 4)
            }
            .font(.system(size: 11))
            .foregroundColor(Theme.dim)
        }
        .card()
        .frame(maxWidth: .infinity)
    }

    // MARK: Pads → multi-effet

    private var padsCard: some View {
        let zones = Zone.allCases
        let onCount = zones.filter { m.zoneState($0)?.mfx == true }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("ZONES QUI PASSENT PAR LE MULTI-EFFET")).font(.system(size: 10, weight: .bold)).foregroundColor(Theme.dim)
                Text("\(onCount)/\(zones.count)").font(.system(size: 10, weight: .bold)).foregroundColor(Theme.accent)
                Spacer()
                Button(L("Toutes")) { m.setAllZonesMFX(true) }.buttonStyle(SoftButtonStyle())
                Button(L("Aucune")) { m.setAllZonesMFX(false) }.buttonStyle(SoftButtonStyle())
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(zones) { z in
                    let on = m.zoneState(z)?.mfx == true
                    FilterChip(label: shortName(z), on: on) { m.setParam(.mfx, on ? 0 : 1, for: z) }
                        .frame(maxWidth: .infinity)
                }
            }
            Text(L("Réglage propre à chaque zone (aussi dans l'inspecteur de l'écran Set). Le multi-effet lui-même est celui du set, ci-dessus."))
                .font(.system(size: 10)).foregroundColor(Theme.dim)
        }
        .card()
    }

    // MARK: Utilitaires

    private func name(_ list: [String], _ v: Int?) -> String {
        guard let v = v else { return "—" }
        return list.indices.contains(v) ? "\(list[v]) (\(v))" : "\(v)"
    }

    private func infoLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundColor(Theme.dim).frame(width: 128, alignment: .leading)
            Text(value).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(Theme.dim)
            Spacer()
        }
        .help(L("Fixé par le HPD-15 selon le type choisi (lecture seule)."))
    }

    private func shortName(_ z: Zone) -> String {
        switch z {
        case .ribbonL: return L("Ruban G")
        case .ribbonR: return L("Ruban D")
        case .dBeam: return "D Beam"
        case .pedal: return L("Pédale")
        case .trig1: return "Trig 1"
        case .trig2: return "Trig 2"
        default: return z.rawValue
        }
    }
}
