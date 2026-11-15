import SwiftUI
import HPD15Core

/// Onglet « Réglages » : couleurs des familles de sons, écoute.
struct SettingsView: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject private var palette = Palette.shared
    @AppStorage(Prefs.auditionOnClick) private var auditionOnClick = true
    @AppStorage(Prefs.auditionOnPick) private var auditionOnPick = true
    @AppStorage(AppLanguage.key) private var appLanguage = "auto"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("Réglages")).font(.system(size: 22, weight: .bold, design: .rounded))

                VStack(alignment: .leading, spacing: 10) {
                    Text(L("LANGUE")).font(.system(size: 10, weight: .bold)).foregroundColor(Theme.dim)
                    Picker(L("Langue de l'interface"), selection: $appLanguage) {
                        Text(L("Automatique (langue du Mac)")).tag("auto")
                        Text("Français").tag("fr")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.radioGroup)
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text(L("ÉCOUTE")).font(.system(size: 10, weight: .bold)).foregroundColor(Theme.dim)
                    Toggle(L("Faire sonner une zone quand on clique dessus"), isOn: $auditionOnClick)
                    Toggle(L("Faire sonner le son choisi dans la liste"), isOn: $auditionOnPick)
                    Text(L("Le son est joué par le HPD-15 lui-même (note envoyée sur le canal des pads)."))
                        .font(.system(size: 11)).foregroundColor(Theme.dim)
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L("COULEURS DES FAMILLES DE SONS")).font(.system(size: 10, weight: .bold)).foregroundColor(Theme.dim)
                        Spacer()
                        Button(L("Couleurs par défaut")) { palette.resetToDefaults() }
                            .buttonStyle(SoftButtonStyle())
                    }
                    ForEach(m.catalog?.categories ?? [], id: \.self) { c in
                        HStack(spacing: 12) {
                            ColorPicker("", selection: Binding(get: { palette.color(c) }, set: { palette.set($0, for: c) }),
                                        supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 44)
                            RoundedRectangle(cornerRadius: 5).fill(palette.color(c).opacity(0.62))
                                .frame(width: 70, height: 22)
                                .overlay(Text(Theme.categoryLabel(c)).font(.system(size: 10, weight: .heavy)).foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.8), radius: 1.5))
                            Text(Theme.categoryLabel(c)).font(.system(size: 13, weight: .medium))
                            Text(example(c)).font(.system(size: 11)).foregroundColor(Theme.dim)
                            Spacer()
                        }
                    }
                }
                .card()
            }
            .padding(14)
            .frame(maxWidth: 640, alignment: .leading)
        }
    }

    /// Trois sons de la famille, pour se repérer.
    private func example(_ c: String) -> String {
        let list = (m.catalog?.instruments ?? []).filter { $0.category == c }
        guard !list.isEmpty else { return "" }
        let picks = [list.first, list.dropFirst(list.count / 2).first, list.dropFirst(list.count - 2).first].compactMap { $0 }
        return picks.map { $0.name }.joined(separator: " · ")
    }
}
