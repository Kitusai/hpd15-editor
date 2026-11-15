import SwiftUI
import AppKit

/// Thème sombre repris de l'éditeur SonicCell.
enum Theme {
    static let bg = Color(red: 0.045, green: 0.048, blue: 0.055)
    static let panel = Color(red: 0.080, green: 0.085, blue: 0.095)
    static let card = Color(red: 0.140, green: 0.152, blue: 0.176)
    static let cardHi = Color(red: 0.175, green: 0.190, blue: 0.218)
    static let stroke = Color.white.opacity(0.07)
    static let accent = Color(red: 1.0, green: 0.62, blue: 0.16)
    static let blue = Color(red: 0.42, green: 0.64, blue: 1.0)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.33)
    static let ok = Color(red: 0.36, green: 0.80, blue: 0.50)
    static let dim = Color.white.opacity(0.55)
    static let cyan = Color(red: 0.0, green: 0.85, blue: 0.95)

    /// Couleur d'une famille de sons : palette réglable (écran « Réglages »).
    static func category(_ c: String?) -> Color { Palette.shared.color(c) }

    /// Nom français d'une catégorie.
    static func categoryLabel(_ c: String) -> String {
        switch c {
        case "Latin": return L("Latin")
        case "African": return L("Afrique")
        case "Indian": return L("Inde")
        case "Asian": return L("Asie")
        case "Orch": return L("Orchestre")
        case "Drums": return L("Batterie")
        case "Dance": return L("Dance")
        case "SFX": return L("Effets")
        case "Others": return L("Mélodiques")
        default: return c
        }
    }
}

struct CardStyle: ViewModifier {
    var highlighted = false
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(highlighted ? Theme.cardHi : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }
}

extension View {
    func card(highlighted: Bool = false) -> some View { modifier(CardStyle(highlighted: highlighted)) }
}

struct Chip: View {
    let text: String
    var color: Color = Color.white.opacity(0.14)
    var textColor: Color = Theme.dim
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(textColor)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color, in: Capsule())
    }
}

/// Puce sélectionnable (filtres de familles).
struct FilterChip: View {
    let label: String
    let on: Bool
    var color: Color = Theme.accent
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(on ? Color.black.opacity(0.85) : Theme.dim)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(on ? color : Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color.black.opacity(0.88))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(tint.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Mémorise position et dimensions de la fenêtre.
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.setFrameUsingName("HPD15Main")
            w.setFrameAutosaveName("HPD15Main")
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
