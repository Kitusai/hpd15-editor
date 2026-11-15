import Foundation
import HPD15Core

// Vérifications sans matériel : `swift run HPD15Checks`

final class FakeHPD: SysExTransport {
    weak var client: HPD15Client?
    var sent: [[UInt8]] = []
    func send(_ bytes: [UInt8]) throws {
        sent.append(bytes)
        guard bytes.count == 16, bytes[5] == 0x11, let a = HPDAddress(bytes: Array(bytes[6..<10])),
              let s = HPDAddress(bytes: Array(bytes[10..<14])) else { return }
        let data = (0..<s.value).map { UInt8($0 & 0x7F) }
        let c = client
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            let half = data.count / 2
            c?.receive(bytes: Roland.dt1(device: 0x10, address: a, data: Array(data[..<half])))
            c?.receive(bytes: [0xFE])
            c?.receive(bytes: Roland.dt1(device: 0x10, address: a.adding(half), data: Array(data[half...])))
        }
    }
}

@main
enum HPD15Checks {
    static var failures = 0

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "OK   " : "ÉCHEC") \(name)\(detail.isEmpty ? "" : " — " + detail)")
        if !ok { failures += 1 }
    }

    static func main() async {
        // 1. Exemples officiels de la doc (p. 109)
        let dt1 = Roland.dt1(device: 0x10, address: HPDAddress(0x01, 0x00, 0x14, 0x10), data: [0x01])
        check("DT1 exemple doc (Trigger Mode A5 = Gate)", dt1 == [0xF0, 0x41, 0x10, 0x00, 0x2E, 0x12, 0x01, 0x00, 0x14, 0x10, 0x01, 0x5A, 0xF7], dt1.hex)
        let rq1 = Roland.rq1(device: 0x10, address: HPDAddress(0x01, 0x00, 0x40, 0x01), size: 1)
        check("RQ1 exemple doc (Resonance Limit)", rq1 == [0xF0, 0x41, 0x10, 0x00, 0x2E, 0x11, 0x01, 0x00, 0x40, 0x01, 0x00, 0x00, 0x00, 0x01, 0x3D, 0xF7], rq1.hex)
        check("RQ1 = 16 octets", rq1.count == 16)

        // 2. Adresses calculées comme dans la doc
        let a5Trig = HPD15Map.tempPatch.adding(PatchMap.zone(.a5) + PatchMap.ZoneParam.triggerMode)
        check("Adresse A5 Trigger Mode = 01 00 14 10", a5Trig.bytes == [0x01, 0x00, 0x14, 0x10], a5Trig.description)
        check("Adresse System MIDI = 00 02 00 00", HPD15Map.systemMIDI.bytes == [0x00, 0x02, 0x00, 0x00])
        check("Adresse U1008 = 12 4F 00 00", HPD15Map.userPatchBulk(79).bytes == [0x12, 0x4F, 0x00, 0x00])
        check("Adresse COMMON = 01 00 40 00", HPD15Map.tempPatch.adding(PatchMap.common).bytes == [0x01, 0x00, 0x40, 0x00])

        // 3. Codage nibblé (exemples doc p. 108)
        check("Nibble 1258 → 00 04 0E 0A", Nibble.encode(1258, count: 4) == [0x00, 0x04, 0x0E, 0x0A])
        check("Nibble 0A 03 09 0D → 41885", Nibble.decode([0x0A, 0x03, 0x09, 0x0D]) == 41885)
        check("Nibble aller-retour 600", Nibble.decode(Nibble.encode(600, count: 4)) == 600)

        // 4. Décodage d'une trame et d'un flux
        switch Roland.parse(dt1) {
        case .dt1(_, let a, let d): check("Parse DT1", a == a5Trig && d == [0x01])
        default: check("Parse DT1", false)
        }
        var bad = dt1; bad[bad.count - 2] = 0x00
        if case .invalid = Roland.parse(bad) { check("Checksum faux détecté", true) } else { check("Checksum faux détecté", false) }
        let idReply: [UInt8] = [0xF0, 0x7E, 0x10, 0x06, 0x02, 0x41, 0x2E, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0xF7]
        if case .identityReply(_, let p) = Roland.parse(idReply) { check("Identity Reply", p.prefix(3) == [0x41, 0x2E, 0x01]) } else { check("Identity Reply", false) }

        var parser = MIDIStreamParser()
        let stream: [UInt8] = [0x99, 0x3C, 0x64, 0x3E, 0x50, 0xFE] + Array(dt1.prefix(5)) + [0xFE] + Array(dt1.dropFirst(5)) + [0xB9, 0x52, 0x10]
        let events = parser.feed(stream)
        check("Flux : running status + Active Sensing + SysEx", events == [
            .channel([0x99, 0x3C, 0x64]), .channel([0x99, 0x3E, 0x50]), .sysex(dt1), .channel([0xB9, 0x52, 0x10])
        ], "\(events.count) événements")

        // 5. Image de patch et décodage d'une zone
        var zone = [UInt8](repeating: 0, count: PatchMap.zoneSize)
        zone.replaceSubrange(0..<4, with: Nibble.encode(10, count: 4))          // L11 Conga Hi
        zone.replaceSubrange(4..<8, with: Nibble.encode(2400 + 150, count: 4))  // +150 cents
        zone[8] = 100
        zone.replaceSubrange(9..<11, with: Nibble.encode(64, count: 2))
        zone[0x0B] = 31
        zone.replaceSubrange(0x23..<0x25, with: Nibble.encode(61, count: 2))
        var image = PatchImage()
        image.absorb(address: HPD15Map.tempPatchBulk.adding(PatchMap.zone(.a1)), data: zone, base: HPD15Map.tempPatchBulk)
        if let s = image.zone(.a1) {
            check("Zone A1 décodée", s.inst == 10 && s.pitchCents == 150 && s.level == 100 && s.panText == "C" && s.decay == 0 && s.midiNoteRaw == 61)
        } else { check("Zone A1 décodée", false) }
        check("Zone A2 absente", image.zone(.a2) == nil)

        // 6. Catalogue
        do {
            let cat = try HPD15Catalog.load()
            check("Catalogue : 601 instruments", cat.instruments.count == 601)
            check("Catalogue : valeur 10 = L11 Conga Hi", cat.instrument(10)?.code == "L11")
            check("Catalogue : 99 Pad Set, 160 presets, 80 users",
                  cat.padSetInstruments.count == 99 && cat.presetPatches.count == 160 && cat.userPatches.count == 80)
            if let p = cat.patch(code: "P0802") { check("P0802 Forest = banque 3 PC 1", p.bankMSB == 2 && p.pc == 0, "MSB \(p.bankMSB) PC \(p.pc)") }
            else { check("P0802 trouvé", false) }
        } catch {
            check("Catalogue chargé", false, error.localizedDescription)
        }

        // 7. Client avec un HPD-15 simulé : réponse découpée en deux DT1
        let fake = FakeHPD()
        let client = HPD15Client(transport: fake)
        fake.client = client
        let read = try? await client.readExact(HPD15Map.tempPatch.adding(PatchMap.zone(.a1)), size: PatchMap.zoneSize, label: "A1")
        check("Client : lecture réassemblée (2 paquets)", read?.count == PatchMap.zoneSize && read?[0x2A] == 0x2A)

        let t0 = Date()
        try? await client.write(HPD15Map.tempPatch, data: [UInt8](repeating: 1, count: 300))
        let dt1Sent = fake.sent.filter { $0.count > 6 && $0[5] == 0x12 }
        check("Écriture 300 octets → 3 paquets ≤ 128", dt1Sent.count == 3 && dt1Sent.allSatisfy { $0.count - 12 <= 128 })
        check("Écriture espacée (≥ 2 × 40 ms)", Date().timeIntervalSince(t0) >= 0.08, String(format: "%.0f ms", Date().timeIntervalSince(t0) * 1000))

        print(failures == 0 ? "\nToutes les vérifications passent." : "\n\(failures) vérification(s) en échec.")
        exit(failures == 0 ? 0 : 1)
    }
}
