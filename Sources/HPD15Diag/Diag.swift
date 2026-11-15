import Foundation
import HPD15Core

/// Journal : écran + fichier `Journaux/diag-AAAAMMJJ-HHMMSS.txt` (à m'envoyer).
final class Journal {
    let url: URL
    private let lock = NSLock()
    private var handle: FileHandle?
    private let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    init() {
        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Journaux")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        url = dir.appendingPathComponent("diag-\(f.string(from: Date())).txt")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    /// Texte destiné à l'utilisateur (écran + fichier).
    func say(_ s: String = "") {
        print(s)
        write(s)
    }

    /// Trame MIDI (fichier seulement, sauf mode bavard).
    func trace(_ e: HPDLogEntry, verbose: Bool) {
        let line = "\(clock.string(from: e.date)) \(e.direction.rawValue) \(e.text)"
        if verbose || e.direction == .error { print("   " + line) }
        write("   " + line)
    }

    private func write(_ s: String) {
        lock.lock()
        handle?.write((s + "\n").data(using: .utf8)!)
        lock.unlock()
    }
}

struct Options {
    var command = "complet"
    var argument: String?
    var portIn = "UM-ONE"
    var portOut = "UM-ONE"
    var device: UInt8 = 0x10
    var channel: Int?
    var verbose = false
    var seconds = 20

    init(_ args: [String]) {
        var i = 0
        var positional: [String] = []
        while i < args.count {
            let a = args[i]
            func next() -> String? { i + 1 < args.count ? args[i + 1] : nil }
            switch a {
            case "--port": if let v = next() { portIn = v; portOut = v; i += 1 }
            case "--in": if let v = next() { portIn = v; i += 1 }
            case "--out": if let v = next() { portOut = v; i += 1 }
            case "--dev": if let v = next(), let b = UInt8(v, radix: 16) { device = b; i += 1 }
            case "--canal": if let v = next(), let c = Int(v) { channel = c; i += 1 }
            case "--secondes": if let v = next(), let s = Int(v) { seconds = s; i += 1 }
            case "-v", "--bavard": verbose = true
            default: positional.append(a)
            }
            i += 1
        }
        if let c = positional.first { command = c }
        if positional.count > 1 { argument = positional[1] }
    }
}

@main
enum HPD15Diag {
    static let journal = Journal()
    static var catalog: HPD15Catalog?
    static var results: [(String, Bool, String)] = []

    static func main() async {
        let opt = Options(Array(CommandLine.arguments.dropFirst()))
        let j = journal
        j.say("HPD-15 — diagnostic MIDI · \(Date())")
        j.say("Commande : \(opt.command)\(opt.argument.map { " " + $0 } ?? "") · Device ID \(String(format: "%02X", opt.device))")

        do { catalog = try HPD15Catalog.load() } catch { j.say("!! Catalogue non chargé : \(error.localizedDescription)") }

        let transport = CoreMIDITransport()
        let srcs = transport.sources(), dsts = transport.destinations()
        j.say("\nEntrées MIDI : " + (srcs.isEmpty ? "(aucune)" : srcs.map { $0.name }.joined(separator: " | ")))
        j.say("Sorties MIDI : " + (dsts.isEmpty ? "(aucune)" : dsts.map { $0.name }.joined(separator: " | ")))
        if opt.command == "ports" { finish(); return }

        guard let src = srcs.first(where: { $0.name.localizedCaseInsensitiveContains(opt.portIn) }),
              let dst = dsts.first(where: { $0.name.localizedCaseInsensitiveContains(opt.portOut) }) else {
            j.say("\n!! Port « \(opt.portIn) » / « \(opt.portOut) » introuvable. Relancez avec --port \"<nom>\".")
            finish(); return
        }
        j.say("Connexion : entrée « \(src.name) », sortie « \(dst.name) »")

        let client = HPD15Client(transport: transport)
        client.deviceByte = opt.device
        client.onLog = { j.trace($0, verbose: opt.verbose) }
        transport.onReceive = { client.receive(bytes: $0) }
        transport.connect(source: src.ref, destination: dst.ref)
        try? await Task.sleep(nanoseconds: 300_000_000)

        do {
            switch opt.command {
            case "complet": try await complete(client, opt)
            case "ecoute":
                _ = try await padChannel(client, opt)
                let image = try await dumpPatch(client, base: HPD15Map.tempPatchBulk, size: HPD15Map.dumpSizeTempPatch, label: "patch temporaire")
                j.say("\nÉcoute pendant \(opt.seconds) s : touchez les zones une par une (ruban G, ruban D, D Beam, pédale…).")
                await listen(client, image: image, seconds: opt.seconds)
            case "ecriture": try await writeTest(client, opt)
            case "cadence": try await cadence(client)
            case "effets": try await effectsExperiment(client)
            case "charger":
                guard let code = opt.argument else { j.say("Usage : charger P0101 (ou U0305)"); break }
                try await loadPatch(client, opt, code: code)
            case "user":
                guard let code = opt.argument, let u = catalog?.userPatches.first(where: { $0.code == code.uppercased() }) else {
                    j.say("Usage : user U0101"); break
                }
                _ = try await dumpPatch(client, base: HPD15Map.userPatchBulk(u.index), size: HPD15Map.dumpSizeUserPatch, label: u.code)
            default:
                j.say("Commandes : complet (défaut) · ports · ecoute · ecriture · cadence · effets · charger P0101 · user U0101")
                j.say("Options : --port UM-ONE · --in … --out … · --dev 10 · --canal 10 · --secondes 20 · -v")
            }
        } catch {
            j.say("\n!! Erreur : \(error.localizedDescription)")
        }
        transport.disconnect()
        finish()
    }

    static func finish() {
        let j = journal
        if !results.isEmpty {
            j.say("\n==== RÉSUMÉ ====")
            for (name, ok, detail) in results { j.say("\(ok ? "OK   " : "ÉCHEC") \(name)\(detail.isEmpty ? "" : " — " + detail)") }
        }
        j.say("\nJournal complet : \(j.url.path)")
        j.say("Merci de m'envoyer ce fichier (même si des étapes échouent).")
    }

    static func record(_ name: String, _ ok: Bool, _ detail: String = "") {
        results.append((name, ok, detail))
    }

    // MARK: - Séquence complète (lecture seule)

    static func complete(_ client: HPD15Client, _ opt: Options) async throws {
        let j = journal

        j.say("\n[1] Identity Request")
        if let p = try await client.identity() {
            let isHPD = p.count >= 3 && p[0] == 0x41 && p[1] == 0x2E
            j.say("    Réponse : \(p.hex) \(isHPD ? "→ HPD-15 reconnu" : "→ appareil inattendu")")
            record("Identity Request", isHPD, p.hex)
        } else {
            j.say("    Pas de réponse.")
            record("Identity Request", false, "pas de réponse")
        }

        j.say("\n[2] Canal MIDI des pads (System MIDI 00 02 00 00, lecture individuelle)")
        let ch = try await padChannel(client, opt)

        j.say("\n[3] Dump du patch temporaire (11 00 00 00)")
        var image = try await dumpPatch(client, base: HPD15Map.tempPatchBulk, size: HPD15Map.dumpSizeTempPatch, label: "patch temporaire")

        j.say("\n[4] Lectures individuelles (01 00 …)")
        var individual = PatchImage()
        for (name, offset, size) in [("PAD A1", PatchMap.zone(.a1), PatchMap.zoneSize),
                                     ("EFFECT", PatchMap.effect, PatchMap.effectSize),
                                     ("COMMON", PatchMap.common, PatchMap.commonSize)] {
            let data = try await client.readExact(HPD15Map.tempPatch.adding(offset), size: size, label: name)
            if let d = data { individual.set(offset, d) }
            j.say("    \(name.padding(toLength: 7, withPad: " ", startingAt: 0)) : \(data == nil ? "pas de réponse complète" : "OK (\(size) octets)")")
            record("RQ1 individuel \(name)", data != nil)
        }
        if individual.has(PatchMap.common, PatchMap.commonSize), !image.has(PatchMap.zone(.c5), PatchMap.zoneSize) {
            j.say("    Le dump est incomplet mais les lectures individuelles marchent : lecture bloc par bloc …")
            for b in PatchMap.blocks where !individual.has(b.offset, b.size) {
                if let d = try await client.readExact(HPD15Map.tempPatch.adding(b.offset), size: b.size, label: b.name) {
                    individual.set(b.offset, d)
                }
            }
            image = individual
        }
        if !image.bytes.isEmpty, individual.has(PatchMap.zone(.a1), PatchMap.zoneSize) {
            let same = image.range(PatchMap.zone(.a1), PatchMap.zoneSize) == individual.range(PatchMap.zone(.a1), PatchMap.zoneSize)
            j.say("    Dump et lecture individuelle de A1 identiques : \(same ? "oui" : "NON")")
        }

        j.say("\n[5] Contenu du patch temporaire")
        printPatch(image)

        j.say("\n[6] Dump d'une mémoire utilisateur (U0101 = 12 00 00 00)")
        let user = try await dumpPatch(client, base: HPD15Map.userPatchBulk(0), size: HPD15Map.dumpSizeUserPatch, label: "U0101")
        if let n = user.name { j.say("    Nom U0101 : « \(n) »") }

        j.say("\n[7] Écoute des pads pendant \(opt.seconds) s (canal \(ch.map { String($0) } ?? "?"))")
        j.say("    → Frappez dans l'ordre A1, A2, A3, A4, A5, B1…B5, C1…C5, puis ruban G, ruban D, D Beam.")
        await listen(client, image: image, seconds: opt.seconds)
    }

    // MARK: - Étapes

    /// Lit le canal MIDI des pads (1…16) ou renvoie `--canal`.
    static func padChannel(_ client: HPD15Client, _ opt: Options) async throws -> Int? {
        let j = journal
        if let d = try await client.readExact(HPD15Map.systemMIDI, size: HPD15Map.systemMIDISize, label: "System MIDI") {
            let raw = Int(d[HPD15Map.SystemMIDIParam.padChannel])
            let names = ["Melo1", "Melo2", "Perc1", "Perc2", "Pad"]
            let text = names.enumerated().map { i, n in "\(n) \(d[i] == 16 ? "OFF" : String(Int(d[i]) + 1))" }.joined(separator: " · ")
            j.say("    \(text) · Local \(d[5] == 1 ? "ON" : "OFF") · Soft Thru \(d[6] == 1 ? "ON" : "OFF")")
            record("Lecture System MIDI", true, "canal Pad = \(raw == 16 ? "OFF" : String(raw + 1))")
            if let c = opt.channel { return c }
            return raw < 16 ? raw + 1 : nil
        }
        j.say("    Pas de réponse.\(opt.channel.map { " Canal imposé : \($0)" } ?? "")")
        record("Lecture System MIDI", false)
        return opt.channel
    }

    /// RQ1 de dump ; décrit précisément les trames reçues (c'est ce que la doc ne dit pas).
    static func dumpPatch(_ client: HPD15Client, base: HPDAddress, size: HPDAddress, label: String) async throws -> PatchImage {
        let j = journal
        let frames = try await client.request(base, size: size, label: label, firstTimeout: 3.0, quiet: 1.0)
        var image = PatchImage()
        guard !frames.isEmpty else {
            j.say("    Aucune trame reçue.")
            record("Dump \(label)", false, "aucune trame")
            return image
        }
        let total = frames.reduce(0) { $0 + $1.data.count }
        j.say("    \(frames.count) trames DT1, \(total) octets :")
        var unplaced = 0
        for f in frames {
            j.say("      \(f.address)  \(String(format: "%3d", f.data.count)) oct")
            // Rangement : soit aux adresses du bloc demandé, soit à celles du patch temporaire individuel.
            if image.absorb(address: f.address, data: f.data, base: base) == 0,
               image.absorb(address: f.address, data: f.data, base: HPD15Map.tempPatch) == 0 {
                unplaced += f.data.count
            }
        }
        if unplaced > 0 { j.say("    \(unplaced) octets à des adresses hors du patch (voir journal).") }
        let covered = PatchMap.blocks.filter { image.has($0.offset, $0.size) }.map { $0.name }
        let missing = PatchMap.blocks.filter { !image.has($0.offset, $0.size) }.map { $0.name }
        j.say("    Blocs complets : \(covered.isEmpty ? "aucun" : covered.joined(separator: ", "))")
        if !missing.isEmpty { j.say("    Blocs manquants : \(missing.joined(separator: ", "))") }
        record("Dump \(label)", missing.isEmpty, "\(frames.count) trames, \(total) octets, \(missing.count) blocs manquants")
        return image
    }

    static func printPatch(_ image: PatchImage) {
        let j = journal
        j.say("    Nom : « \(image.name ?? "?") »")
        if let e = image.range(PatchMap.effect, PatchMap.effectSize), let c = image.range(PatchMap.common, PatchMap.commonSize) {
            j.say("    Master Volume \(c[0]) · Multi-Effets \(c[PatchMap.CommonParam.multiEffects] == 1 ? "ON" : "OFF") · Reverb algo \(e[2]) niveau \(e[3]) · M-FX type \(e[7]) algo \(e[9])")
        }
        j.say("    Zone      Inst   Code  Nom            Niv Pan  Pitch Dec Rev MFX Note")
        for z in Zone.allCases {
            guard let s = image.zone(z) else { j.say("    \(z.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) (non reçu)"); continue }
            let inst = catalog?.instrument(s.inst)
            let cols = [
                z.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0),
                String(format: "%4d", s.inst),
                (inst?.code ?? "?").padding(toLength: 5, withPad: " ", startingAt: 0),
                (inst?.name ?? "?").padding(toLength: 14, withPad: " ", startingAt: 0),
                String(format: "%3d", s.level),
                s.panText.padding(toLength: 4, withPad: " ", startingAt: 0),
                String(format: "%5d", s.pitchCents),
                String(format: "%3d", s.decay),
                String(format: "%3d", s.reverbSend),
                s.mfx ? "on " : "off",
                s.midiNoteRaw > 127 ? "OFF" : "\(s.midiNoteRaw) \(noteName(s.midiNoteRaw))"
            ]
            j.say("    " + cols.joined(separator: " "))
        }
    }

    /// Affiche les messages de canal reçus et propose la zone correspondante.
    static func listen(_ client: HPD15Client, image: PatchImage?, seconds: Int) async {
        let j = journal
        // Validé le 2026-11-14 : la valeur stockée (offset 23-24) est le numéro de note MIDI tel quel.
        var byNote: [Int: [String]] = [:]
        for z in Zone.allCases {
            if let s = image?.zone(z), s.midiNoteRaw <= 127 {
                byNote[s.midiNoteRaw, default: []].append(z.rawValue)
            }
        }
        let map = byNote
        client.onChannelMessage = { m in
            let ch = Int(m[0] & 0x0F) + 1
            switch m[0] & 0xF0 {
            case 0x90 where m.count == 3 && m[2] > 0:
                let n = Int(m[1])
                j.say("    Note On  ch \(ch) note \(n) (\(noteName(n))) vél \(m[2]) → \(map[n]?.joined(separator: " / ") ?? "zone inconnue")")
            case 0x80, 0x90:
                break
            case 0xB0:
                j.say("    CC       ch \(ch) n° \(m[1]) = \(m[2])")
            case 0xA0:
                break                               // pression polyphonique : trop bavard
            default:
                j.say("    \(m.hex)")
            }
        }
        try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        client.onChannelMessage = nil
        j.say("    Fin de l'écoute.")
    }

    // MARK: - Mesure du silence nécessaire après une réponse

    /// Lit COMMON, attend `gap` après la réponse, relit sans renvoi : la 2e lecture est-elle servie ?
    static func cadence(_ client: HPD15Client) async throws {
        let j = journal
        let addr = HPD15Map.tempPatch.adding(PatchMap.common)
        let saved = client.turnaround
        client.turnaround = 0.5
        j.say("\n[K] Délai minimal entre une réponse du HPD-15 et la requête suivante")
        var minimalOK: Double?
        for gap in [0.03, 0.06, 0.1, 0.15, 0.2, 0.3] {
            var answered = 0
            for _ in 0..<3 {
                client.turnaround = 0.5
                guard try await client.readExact(addr, size: PatchMap.commonSize, label: "COMMON (amorce)", retries: 2) != nil else { continue }
                let target = client.lastReceive.addingTimeInterval(gap)
                let wait = target.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                client.turnaround = 0
                if try await client.readExact(addr, size: PatchMap.commonSize, label: "COMMON (+\(Int(gap * 1000)) ms)", retries: 0) != nil {
                    answered += 1
                }
            }
            j.say("    \(String(format: "%4d", Int(gap * 1000))) ms : \(answered)/3 réponses")
            if answered == 3, minimalOK == nil { minimalOK = gap }
        }
        client.turnaround = saved
        record("Cadence", minimalOK != nil, minimalOK.map { "délai suffisant dès \(Int($0 * 1000)) ms" } ?? "aucun délai testé ne suffit")
    }

    // MARK: - Expérience « effets » (interactive)

    /// Lit le bloc EFFECT (24 octets) et l'octet MULTI EFFECTS (COMMON 08).
    static func readEffects(_ client: HPD15Client) async throws -> (effect: [UInt8], mfxOn: UInt8)? {
        guard let e = try await client.readExact(HPD15Map.tempPatch.adding(PatchMap.effect), size: PatchMap.effectSize, label: "EFFECT", retries: 2),
              let c = try await client.readExact(HPD15Map.tempPatch.adding(PatchMap.common), size: PatchMap.commonSize, label: "COMMON", retries: 2)
        else { return nil }
        return (e, c[PatchMap.CommonParam.multiEffects])
    }

    static func describe(_ e: [UInt8], _ on: UInt8) -> String {
        let rt = Int(e[0]), mt = Int(e[7]), algo = Int(e[9])
        let rName = PatchMap.reverbTypeName(rt)
        let aName = PatchMap.mfxAlgorithmNames.indices.contains(algo) ? PatchMap.mfxAlgorithmNames[algo] : "?"
        let onText = on == 1 ? "ON" : "OFF"
        return "Reverb type \(rt) (\(rName)) · M-FX \(onText) type \(mt) (\(PatchMap.mfxTypeName(mt))) · algo \(algo) (\(aName))"
    }

    static func ask(_ question: String) -> String {
        journal.say("\n>>> " + question)
        print("    (réponse puis Entrée) ", terminator: "")
        let r = readLine() ?? ""
        journal.say("    Réponse : \(r)")
        return r
    }

    static func writeEffects(_ client: HPD15Client, _ e: [UInt8], _ on: UInt8, label: String) async throws {
        try await client.write(HPD15Map.tempPatch.adding(PatchMap.effect), data: e, label: "DT1 EFFECT \(label)")
        try await client.write(HPD15Map.tempPatch.adding(PatchMap.common + PatchMap.CommonParam.multiEffects), data: [on], label: "DT1 MULTI EFFECTS")
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    static func effectsExperiment(_ client: HPD15Client) async throws {
        let j = journal
        j.say("\n[F1] État initial des effets")
        guard let a = try await readEffects(client) else { j.say("    Lecture impossible."); return }
        j.say("    " + describe(a.effect, a.mfxOn))
        j.say("    Octets : \(a.effect.hex)")

        _ = ask("Sur le HPD-15 : [EDIT] (EZ Edit) → REVERB Type = WarmRoom ; MULTI-FX Type = Stereo Cho ; bouton [MULTI EFFECTS] allumé ; [EXIT]. Vérifiez en frappant un pad que les effets s'entendent. Notez ce qu'affiche l'écran pour le type M-FX, puis tapez « ok ».")
        guard let b = try await readEffects(client) else { j.say("    Lecture impossible."); return }
        j.say("\n[F2] État après réglage sur l'appareil")
        j.say("    " + describe(b.effect, b.mfxOn))
        j.say("    Octets : \(b.effect.hex)")
        j.say("    Octets modifiés par l'appareil :")
        for i in 0..<PatchMap.effectSize where a.effect[i] != b.effect[i] {
            j.say("      offset \(String(format: "%02X", i)) : \(a.effect[i]) → \(b.effect[i])")
        }
        if a.mfxOn != b.mfxOn { j.say("      MULTI EFFECTS : \(a.mfxOn) → \(b.mfxOn)") }
        record("Effets : relevé du réglage fait sur l'appareil", true, describe(b.effect, b.mfxOn))

        j.say("\n[F3] Retour à l'état initial par écriture du bloc complet")
        try await writeEffects(client, a.effect, a.mfxOn, label: "(initial)")
        let r3 = ask("Frappez un pad : les effets ont-ils DISPARU ? (o/n)")
        record("Écriture du bloc complet → état initial", r3.lowercased().hasPrefix("o"), r3)

        j.say("\n[F4] Retour aux effets réglés sur l'appareil, par écriture du bloc complet")
        try await writeEffects(client, b.effect, b.mfxOn, label: "(réglé)")
        let r4 = ask("Frappez un pad : les effets sont-ils REVENUS ? (o/n)")
        record("Écriture du bloc complet → effets", r4.lowercased().hasPrefix("o"), r4)

        j.say("\n[F5] État initial, puis écriture des seuls octets « type » (00 et 07) + MULTI EFFECTS")
        try await writeEffects(client, a.effect, a.mfxOn, label: "(initial)")
        try await client.write(HPD15Map.tempPatch.adding(PatchMap.effect), data: [b.effect[0]], label: "DT1 Reverb type")
        try await client.write(HPD15Map.tempPatch.adding(PatchMap.effect + 7), data: [b.effect[7]], label: "DT1 M-FX type")
        try await client.write(HPD15Map.tempPatch.adding(PatchMap.common + PatchMap.CommonParam.multiEffects), data: [b.mfxOn], label: "DT1 MULTI EFFECTS")
        try? await Task.sleep(nanoseconds: 600_000_000)
        if let c = try await readEffects(client) {
            j.say("    Relu : " + describe(c.effect, c.mfxOn))
            j.say("    Octets : \(c.effect.hex)")
        }
        let r5 = ask("Frappez un pad : les effets s'entendent-ils ? (o/n)")
        record("Écriture des seuls octets type", r5.lowercased().hasPrefix("o"), r5)

        j.say("\n[F6] Restauration de l'état initial")
        try await writeEffects(client, a.effect, a.mfxOn, label: "(initial)")
        j.say("    Terminé.")
    }

    // MARK: - Test d'écriture (patch temporaire seulement, valeur restaurée)

    static func writeTest(_ client: HPD15Client, _ opt: Options) async throws {
        let j = journal
        let addr = HPD15Map.tempPatch.adding(PatchMap.zone(.a1) + PatchMap.ZoneParam.inst)
        j.say("\n[E1] Lecture de l'instrument du pad A1 (\(addr))")
        guard let before = try await client.readExact(addr, size: 4, label: "A1 Inst") else {
            j.say("    Pas de réponse : test d'écriture impossible sans relecture.")
            record("Écriture A1", false, "lecture impossible")
            return
        }
        let original = Nibble.decode(before)
        let target = original < 599 ? original + 1 : original - 1
        j.say("    Actuel : \(original) \(catalog?.instrument(original).map { "\($0.code) \($0.name)" } ?? "")")
        j.say("\n[E2] Écriture : \(target) \(catalog?.instrument(target).map { "\($0.code) \($0.name)" } ?? "")")
        try await client.write(addr, data: Nibble.encode(target, count: 4), label: "DT1 A1 Inst")
        try? await Task.sleep(nanoseconds: 300_000_000)
        let after = try await client.readExact(addr, size: 4, label: "A1 Inst")
        let ok = after.map { Nibble.decode($0) } == target
        j.say("    Relecture : \(after.map { String(Nibble.decode($0)) } ?? "pas de réponse") → \(ok ? "écriture confirmée" : "NON confirmée")")
        record("Écriture A1 (relecture)", ok)
        j.say("\n[E3] Frappez le pad A1 pendant 8 s : vous devez entendre « \(catalog?.instrument(target)?.name ?? "?") »")
        await listen(client, image: nil, seconds: 8)
        j.say("\n[E4] Restauration de la valeur d'origine")
        try await client.write(addr, data: before, label: "DT1 A1 Inst (restauration)")
        try? await Task.sleep(nanoseconds: 300_000_000)
        let restored = try await client.readExact(addr, size: 4, label: "A1 Inst")
        let rok = restored == before
        j.say("    \(rok ? "Restauré." : "!! Restauration NON confirmée : vérifiez le son du pad A1 sur l'appareil.")")
        record("Restauration A1", rok)
    }

    // MARK: - Chargement d'un patch preset ou user par Bank Select + Program Change

    static func loadPatch(_ client: HPD15Client, _ opt: Options, code: String) async throws {
        let j = journal
        guard let p = catalog?.patch(code: code) else { j.say("Code inconnu : \(code)"); return }
        j.say("\n[C1] Canal des pads")
        guard let ch = try await padChannel(client, opt) else {
            j.say("    Canal inconnu : relancez avec --canal <1-16>.")
            return
        }
        j.say("\n[C2] Sélection de \(code.uppercased()) « \(p.name) » : Bank MSB \(p.bankMSB), PC \(p.pc + 1), canal \(ch)")
        try await client.sendRaw(MIDIMessage.bankProgram(channel: ch, msb: p.bankMSB, program: p.pc), label: "Bank/PC")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        j.say("    → L'écran du HPD-15 doit afficher \(code.uppercased()).")
        j.say("\n[C3] Lecture du patch temporaire")
        var image = try await dumpPatch(client, base: HPD15Map.tempPatchBulk, size: HPD15Map.dumpSizeTempPatch, label: "patch temporaire")
        if image.bytes.isEmpty {
            for b in PatchMap.blocks {
                if let d = try await client.readExact(HPD15Map.tempPatch.adding(b.offset), size: b.size, label: b.name) { image.set(b.offset, d) }
            }
        }
        printPatch(image)
        if code.uppercased().hasPrefix("P") {
            let match = image.name?.lowercased() == p.name.lowercased()
            record("Chargement \(code.uppercased())", match, "nom lu « \(image.name ?? "?") », attendu « \(p.name) »")
        }
    }
}
