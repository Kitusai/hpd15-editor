import SwiftUI
import HPD15Core

/// Secteur d'anneau. Angles SwiftUI (0° = droite, sens horaire à l'écran), rayons en fraction du rayon total.
struct RingSector: Shape {
    var start: Double
    var end: Double
    var inner: CGFloat
    var outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        p.addArc(center: c, radius: r * outer, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        if inner > 0 {
            p.addArc(center: c, radius: r * inner, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        } else {
            p.addLine(to: c)
        }
        p.closeSubpath()
        return p
    }
}

/// Disque central (A3).
struct CenterDisc: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2 * radius
        return Path(ellipseIn: CGRect(x: rect.midX - r, y: rect.midY - r, width: 2 * r, height: 2 * r))
    }
}

/// Géométrie de la surface du HPD-15 (manuel p. 15).
enum PadGeometry {
    static let ringInner: CGFloat = 0.80
    static let centerRadius: CGFloat = 0.22

    /// Forme de chaque pad, et position de son étiquette (angle, rayon relatif).
    static func shape(_ z: Zone) -> (shape: ErasedShape, labelAngle: Double, labelRadius: CGFloat) {
        switch z {
        case .a1: return (ErasedShape(RingSector(start: 90, end: 180, inner: 0, outer: 1)), 135, 0.55)
        case .a5: return (ErasedShape(RingSector(start: 0, end: 90, inner: 0, outer: 1)), 45, 0.55)
        case .a2: return (ErasedShape(RingSector(start: 180, end: 270, inner: 0, outer: ringInner)), 225, 0.52)
        case .a4: return (ErasedShape(RingSector(start: 270, end: 360, inner: 0, outer: ringInner)), 315, 0.52)
        case .a3: return (ErasedShape(CenterDisc(radius: centerRadius)), 0, 0)
        default:
            // Anneau supérieur : B1 (à gauche) … B5 (en haut), C1 (en haut) … C5 (à droite), 18° chacun.
            let order: [Zone] = [.b1, .b2, .b3, .b4, .b5, .c1, .c2, .c3, .c4, .c5]
            let i = order.firstIndex(of: z) ?? 0
            let s = 180 + Double(i) * 18
            return (ErasedShape(RingSector(start: s, end: s + 18, inner: ringInner, outer: 1)), s + 9, (1 + ringInner) / 2)
        }
    }
}

/// Forme « effacée » (AnyShape n'existe qu'à partir de macOS 13).
struct ErasedShape: Shape {
    private let make: (CGRect) -> Path
    init<S: Shape>(_ s: S) { make = { s.path(in: $0) } }
    func path(in rect: CGRect) -> Path { make(rect) }
}

/// Représentation interactive du HPD-15 : clic = sélection, clic sur la zone déjà sélectionnée = écoute.
struct SurfaceView: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject private var palette = Palette.shared
    /// Fond opaque de chaque zone : les traits des zones voisines ne transparaissent plus (A3).
    private let base = Color(white: 0.13)

    private let pads: [Zone] = [.a1, .a5, .a2, .a4, .b1, .b2, .b3, .b4, .b5, .c1, .c2, .c3, .c4, .c5, .a3]

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width * 0.70, geo.size.height * 0.74)
            let cx = geo.size.width / 2
            let cy = geo.size.height * 0.48
            ZStack {
                // Corps de l'appareil
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.20), Color(white: 0.07)], center: .center, startRadius: 0, endRadius: d * 0.62))
                    .frame(width: d * 1.10, height: d * 1.10)
                    .shadow(color: .black.opacity(0.7), radius: 12, y: 6)
                    .position(x: cx, y: cy)

                ZStack {
                    ForEach(pads, id: \.self) { z in padView(z, diameter: d) }
                }
                .frame(width: d, height: d)
                .position(x: cx, y: cy)

                // Rubans
                stripView(.ribbonL, label: L("RUBAN G"), width: d * 0.075, height: d * 0.62)
                    .position(x: cx - d * 0.66, y: cy)
                stripView(.ribbonR, label: L("RUBAN D"), width: d * 0.075, height: d * 0.62)
                    .position(x: cx + d * 0.66, y: cy)
                // D Beam
                stripView(.dBeam, label: "D BEAM", width: d * 0.34, height: d * 0.075)
                    .position(x: cx, y: cy - d * 0.64)
                // Pédale et déclencheurs externes
                HStack(spacing: d * 0.04) {
                    stripView(.pedal, label: L("PÉDALE"), width: d * 0.22, height: d * 0.07)
                    stripView(.trig1, label: "TRIG 1", width: d * 0.22, height: d * 0.07)
                    stripView(.trig2, label: "TRIG 2", width: d * 0.22, height: d * 0.07)
                }
                .position(x: cx, y: cy + d * 0.66)
            }
        }
    }

    private func zoneColor(_ z: Zone) -> Color {
        if m.flashZone == z { return Color.white.opacity(0.95) }
        guard m.zoneState(z) != nil else { return Color.white.opacity(0.06) }
        let cat = m.zoneState(z).flatMap { m.instrument($0.inst)?.category }
        return palette.color(cat).opacity(m.selectedZone == z ? 1.0 : 0.62)
    }

    /// Clic : sélection, et écoute si l'option est active (sinon : second clic = écoute).
    private func tap(_ z: Zone) {
        if Prefs.bool(Prefs.auditionOnClick) || m.selectedZone == z { m.audition(z) }
        m.selectedZone = z
        m.flash(z)
    }

    @ViewBuilder
    private func padView(_ z: Zone, diameter d: CGFloat) -> some View {
        let g = PadGeometry.shape(z)
        let selected = m.selectedZone == z
        let a = g.labelAngle * .pi / 180
        let lx = d / 2 + CGFloat(cos(a)) * d / 2 * g.labelRadius
        let ly = d / 2 + CGFloat(sin(a)) * d / 2 * g.labelRadius
        let inst = m.zoneState(z).flatMap { m.instrument($0.inst) }
        ZStack {
            g.shape.fill(base)
            g.shape.fill(zoneColor(z))
            g.shape.stroke(Theme.bg, lineWidth: 2.5)
            if selected { g.shape.stroke(Color.white, lineWidth: 3) }
            VStack(spacing: 1) {
                Text(z.rawValue).font(.system(size: z.isRingPad ? 10 : 13, weight: .heavy, design: .rounded))
                if !z.isRingPad, let i = inst {
                    Text(i.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                }
            }
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.8), radius: 1.5)
            .frame(width: z.isRingPad ? d * 0.12 : d * 0.30)
            .position(x: lx, y: ly)
            .allowsHitTesting(false)
        }
        .contentShape(g.shape)
        .onTapGesture { tap(z) }
        .help(inst.map { "\(z.rawValue) · \($0.code) \($0.name)" } ?? z.rawValue)
    }

    private func stripView(_ z: Zone, label: String, width: CGFloat, height: CGFloat) -> some View {
        let selected = m.selectedZone == z
        let inst = m.zoneState(z).flatMap { m.instrument($0.inst) }
        let vertical = height > width
        return ZStack {
            RoundedRectangle(cornerRadius: min(width, height) / 2).fill(base)
            RoundedRectangle(cornerRadius: min(width, height) / 2).fill(zoneColor(z))
            RoundedRectangle(cornerRadius: min(width, height) / 2)
                .stroke(selected ? Color.white : Color.white.opacity(0.12), lineWidth: selected ? 3 : 1)
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.8), radius: 1.5)
                .fixedSize()
                .rotationEffect(.degrees(vertical ? -90 : 0))
                .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
        .contentShape(RoundedRectangle(cornerRadius: min(width, height) / 2))
        .onTapGesture { tap(z) }
        .help(inst.map { "\(label) · \($0.code) \($0.name)" } ?? label)
    }
}

extension Zone {
    /// Pads de l'anneau supérieur (petits secteurs).
    var isRingPad: Bool { rawValue.hasPrefix("B") || rawValue.hasPrefix("C") }
}
