import SwiftUI
import AppKit

// MARK: - Palette des familles de sons (modifiable dans « Réglages »)

final class Palette: ObservableObject {
    static let shared = Palette()

    /// Couleurs par défaut, vives (le brun venait d'un orange trop transparent sur fond sombre).
    static let defaults: [String: (Double, Double, Double)] = [
        "Latin": (0.98, 0.42, 0.38),     // corail
        "African": (0.96, 0.76, 0.22),   // ambre
        "Indian": (0.93, 0.36, 0.70),    // magenta
        "Asian": (0.66, 0.48, 0.98),     // violet
        "Orch": (0.36, 0.62, 1.00),      // bleu
        "Drums": (0.22, 0.82, 0.80),     // turquoise
        "Dance": (0.40, 0.88, 0.42),     // vert
        "SFX": (0.62, 0.66, 0.78),       // gris bleuté
        "Others": (0.86, 0.90, 0.36)     // anis
    ]

    @Published private(set) var colors: [String: Color] = [:]

    private init() { load() }

    func color(_ category: String?) -> Color {
        guard let c = category else { return Color(white: 0.35) }
        return colors[c] ?? Color(white: 0.45)
    }

    func set(_ color: Color, for category: String) {
        colors[category] = color
        save()
    }

    func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: "paletteRGB")
        load()
    }

    private func load() {
        var out: [String: Color] = [:]
        let saved = UserDefaults.standard.dictionary(forKey: "paletteRGB") as? [String: [Double]] ?? [:]
        for (k, d) in Self.defaults {
            if let v = saved[k], v.count == 3 {
                out[k] = Color(red: v[0], green: v[1], blue: v[2])
            } else {
                out[k] = Color(red: d.0, green: d.1, blue: d.2)
            }
        }
        colors = out
    }

    private func save() {
        var dict: [String: [Double]] = [:]
        for (k, c) in colors {
            if let n = NSColor(c).usingColorSpace(.sRGB) {
                dict[k] = [Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent)]
            }
        }
        UserDefaults.standard.set(dict, forKey: "paletteRGB")
    }
}

// MARK: - Préférences d'écoute

enum Prefs {
    /// Un clic sur une zone du dessin la fait sonner.
    static let auditionOnClick = "auditionOnClick"
    /// Choisir un son dans la liste le fait sonner.
    static let auditionOnPick = "auditionOnPick"

    static func bool(_ key: String, default value: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? value : UserDefaults.standard.bool(forKey: key)
    }
}

// MARK: - Curseur horizontal (clic/glisser, double-clic = valeur par défaut)

/// Détecte un double-clic à partir d'un geste de glissement.
struct DoubleClickTracker {
    var last: Date?
    mutating func register(moved: CGFloat) -> Bool {
        guard moved < 3 else { last = nil; return false }
        let now = Date()
        defer { last = now }
        if let l = last, now.timeIntervalSince(l) < 0.4 { last = nil; return true }
        return false
    }
}

struct HSlider: View {
    let value: Int
    let range: ClosedRange<Int>
    var defaultValue: Int
    var step: Int = 1
    var tint: Color = Theme.accent
    /// Valeur de départ du remplissage (0 pour un réglage signé, sinon le minimum).
    var origin: Int? = nil
    var disabled = false
    let onChange: (Int) -> Void

    @State private var clicks = DoubleClickTracker()

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width - 14)
            let span = Double(range.upperBound - range.lowerBound)
            let frac = { (v: Int) in CGFloat(Double(v - range.lowerBound) / span) }
            let x = 7 + w * frac(min(range.upperBound, max(range.lowerBound, value)))
            let x0 = 7 + w * frac(origin ?? range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 4).padding(.horizontal, 7)
                Rectangle().fill(tint.opacity(disabled ? 0.3 : 0.9))
                    .frame(width: abs(x - x0), height: 4)
                    .offset(x: min(x, x0))
                Circle()
                    .fill(disabled ? Color(white: 0.4) : Color.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .offset(x: x - 7)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard !disabled else { return }
                    let f = Double(min(max(0, g.location.x - 7), w) / w)
                    var v = Double(range.lowerBound) + f * span
                    v = (v / Double(step)).rounded() * Double(step)
                    let iv = min(range.upperBound, max(range.lowerBound, Int(v)))
                    if iv != value { onChange(iv) }
                }
                .onEnded { g in
                    guard !disabled else { return }
                    if clicks.register(moved: hypot(g.translation.width, g.translation.height)) {
                        onChange(defaultValue)
                    }
                })
        }
        .frame(height: 18)
        .help(Lf("Double-clic : valeur par défaut (%d)", defaultValue))
    }
}
