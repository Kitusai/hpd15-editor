import Foundation
import AppKit
import CoreMIDI
import SwiftUI
import HPD15Core

/// Journal MIDI isolé du modèle principal : ses mises à jour ne redessinent pas l'interface.
@MainActor final class JournalStore: ObservableObject {
    @Published var lines: [LogLine] = []
    func append(_ l: LogLine) {
        lines.append(l)
        if lines.count > 3000 { lines.removeFirst(lines.count - 3000) }
    }
}

struct LogLine: Identifiable {
    let id = UUID()
    let time: String
    let direction: HPDLogEntry.Direction
    let text: String
    var plain: String { "\(time) \(direction.rawValue) \(text)" }
}

enum Screen: String, CaseIterable, Identifiable {
    case set = "Set"
    case effects = "Effets du set"
    case library = "Bibliothèque"
    case settings = "Réglages"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .set: return "circle.grid.cross"
        case .effects: return "sparkles"
        case .library: return "folder"
        case .settings: return "slider.horizontal.3"
        }
    }
}

/// Paramètre d'une zone éditable dans l'inspecteur.
enum ZoneParam {
    case level, pitch, pan, decay, sweep, color, reverb, mfx

    var offset: Int {
        typealias P = PatchMap.ZoneParam
        switch self {
        case .level: return P.level
        case .pitch: return P.pitch
        case .pan: return P.pan
        case .decay: return P.decay
        case .sweep: return P.sweep
        case .color: return P.color
        case .reverb: return P.reverbSend
        case .mfx: return P.mfxSwitch
        }
    }

    /// Valeur affichée → octets à écrire.
    func encode(_ v: Int) -> [UInt8] {
        switch self {
        case .pitch: return Nibble.encode(max(-2400, min(2400, v)) + 2400, count: 4)
        case .pan: return Nibble.encode(max(1, min(129, v)), count: 2)
        case .decay, .sweep, .color: return [UInt8(max(-31, min(31, v)) + 31)]
        case .mfx: return [v != 0 ? 1 : 0]
        case .level, .reverb: return [UInt8(max(0, min(127, v)))]
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    // Connexion
    @Published var sources: [MIDIPortInfo] = []
    @Published var destinations: [MIDIPortInfo] = []
    @Published var selectedSource: MIDIEndpointRef = 0
    @Published var selectedDestination: MIDIEndpointRef = 0
    @Published var deviceNumber: Int = 17 {            // 1…32 (écran du HPD-15)
        didSet {
            client.deviceByte = UInt8(max(1, min(32, deviceNumber)) - 1)
            UserDefaults.standard.set(deviceNumber, forKey: "deviceNumber")
        }
    }
    @Published var connected = false
    @Published var deviceFound = false
    @Published var padChannel: Int?                    // 1…16, lu dans le système du HPD-15

    // Set en cours (image du patch temporaire du HPD-15)
    @Published var image = PatchImage()
    @Published var origin = ""                         // « P0101 Conga », « U0305 », « HPD-15 »…
    @Published var dirty = false
    /// Fichier de la bibliothèque dont vient le set (Enregistrer l'écrase).
    @Published var loadedEntryID: UUID?
    @Published var selectedZone: Zone = .a1
    @Published var flashZone: Zone?
    private var noteMap: [Int: Zone] = [:]

    // Interface
    @Published var screen: Screen = .set
    @Published var busy = false
    @Published var progress = ""
    @Published var errorMessage: String?
    @Published var notice: String?
    let journal = JournalStore()
    let library = LibraryStore()

    let catalog: HPD15Catalog?
    let transport = CoreMIDITransport()
    let client: HPD15Client

    private let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()
    private var pendingWrites: [Int: Int] = [:]        // offset → nombre d'octets
    private var writers: Set<Int> = []
    private var flashTask: Task<Void, Never>?

    init() {
        catalog = try? HPD15Catalog.load()
        client = HPD15Client(transport: transport)
        let c = client
        transport.onReceive = { bytes in c.receive(bytes: bytes) }
        transport.onSetupChanged = { [weak self] in
            DispatchQueue.main.async { self?.refreshPorts() }
        }
        client.onLog = { [weak self] entry in
            DispatchQueue.main.async { self?.log(entry) }
        }
        client.onChannelMessage = { [weak self] msg in
            DispatchQueue.main.async { self?.handleChannel(msg) }
        }
        if UserDefaults.standard.object(forKey: "deviceNumber") != nil {
            deviceNumber = max(1, UserDefaults.standard.integer(forKey: "deviceNumber"))
        }
        client.deviceByte = UInt8(deviceNumber - 1)
        if catalog == nil { errorMessage = L("Le catalogue des sons (catalog-hpd15.json) est introuvable.") }
        refreshPorts()
        if selectedDestination != 0 {
            connect()
            readFromDevice()
        }
    }

    // MARK: - Catalogue

    func instrument(_ value: Int) -> HPD15Catalog.Instrument? { catalog?.instrument(value) }

    func zoneState(_ z: Zone) -> ZoneState? { image.zone(z) }

    // MARK: - Ports

    func refreshPorts() {
        sources = transport.sources()
        destinations = transport.destinations()
        func pick(_ list: [MIDIPortInfo], current: MIDIEndpointRef, key: String) -> MIDIEndpointRef {
            if current != 0, list.contains(where: { $0.ref == current }) { return current }
            if let name = UserDefaults.standard.string(forKey: key), let m = list.first(where: { $0.name == name }) { return m.ref }
            if let m = list.first(where: { $0.name.lowercased().contains("um-one") }) { return m.ref }
            return 0
        }
        selectedSource = pick(sources, current: selectedSource, key: "srcName")
        selectedDestination = pick(destinations, current: selectedDestination, key: "dstName")
        if connected { connect() }
    }

    func connect() {
        transport.connect(source: selectedSource, destination: selectedDestination)
        connected = selectedDestination != 0 && selectedSource != 0
        let src = sources.first(where: { $0.ref == selectedSource })?.name ?? "aucune"
        let dst = destinations.first(where: { $0.ref == selectedDestination })?.name ?? "aucune"
        UserDefaults.standard.set(src, forKey: "srcName")
        UserDefaults.standard.set(dst, forKey: "dstName")
        log(HPDLogEntry(.info, Lf("Connexion — entrée : %@ · sortie : %@ · Device ID %d", src, dst, deviceNumber)))
    }

    // MARK: - Opérations longues (une seule à la fois)

    private func run(_ label: String, _ work: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            guard !self.busy else { return }
            self.busy = true
            self.progress = label + "…"
            do {
                try await work()
            } catch {
                self.errorMessage = "\(label) : \(error.localizedDescription)"
                self.log(HPDLogEntry(.error, "\(label) : \(error.localizedDescription)"))
            }
            self.progress = ""
            self.busy = false
        }
    }

    private func pause(_ ms: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }

    // MARK: - Lecture depuis le HPD-15

    /// Canal MIDI des pads (System MIDI, octet 04).
    private func readPadChannel() async throws {
        guard let d = try await client.readExact(HPD15Map.systemMIDI, size: HPD15Map.systemMIDISize, label: "System MIDI", retries: 2) else {
            throw HPDError.invalid(L("le HPD-15 ne répond pas. Vérifiez le câblage MIDI (UM-ONE) et le Device ID."))
        }
        let raw = Int(d[HPD15Map.SystemMIDIParam.padChannel])
        padChannel = raw < 16 ? raw + 1 : nil
        deviceFound = true
    }

    /// Dump complet du patch temporaire (27 trames, ~2 s), avec un nouvel essai si incomplet.
    private func dumpTemporaryPatch() async throws -> PatchImage {
        var last = PatchImage()
        for attempt in 0..<2 {
            if attempt > 0 { await pause(300) }
            let frames = try await client.request(HPD15Map.tempPatchBulk, size: HPD15Map.dumpSizeTempPatch,
                                                  label: "patch temporaire", firstTimeout: 1.5, quiet: 0.5)
            var img = PatchImage()
            for f in frames { img.absorb(address: f.address, data: f.data, base: HPD15Map.tempPatchBulk) }
            if img.isComplete { return img }
            last = img
        }
        throw HPDError.invalid(Lf("lecture incomplète (manquent : %@).", last.missingBlocks.joined(separator: ", ")))
    }

    private func adopt(_ img: PatchImage, origin: String, entry: UUID? = nil) {
        image = img
        noteMap = img.noteMap
        self.origin = origin
        loadedEntryID = entry
        dirty = false
    }

    // MARK: - Bibliothèque

    var loadedEntry: LibraryStore.Entry? { library.entry(loadedEntryID) }

    /// Enregistrer : écrase le fichier chargé (informations du fichier conservées).
    func save() {
        guard let e = loadedEntry, !busy else { return }
        guard image.isComplete else { errorMessage = L("Le set n'est pas complet : relisez le HPD-15."); return }
        let name = image.name.map { $0.isEmpty ? e.item.name : $0 } ?? e.item.name
        // Le nom du fichier peut être plus long que les 10 caractères de l'appareil : on le garde s'il commence pareil.
        let fileName = e.item.name.hasPrefix(name) ? e.item.name : name
        let s = StoredSet.make(from: image, name: fileName, details: e.item.details, tags: e.item.tags,
                               origin: e.item.origin, catalog: catalog, id: e.item.id, created: e.item.created)
        do {
            let ne = try library.update(e, with: s)
            loadedEntryID = ne.id
            origin = Lf("Fichier « %@ »", ne.item.name)
            dirty = false
        } catch {
            errorMessage = Lf("Enregistrement : %@", error.localizedDescription)
        }
    }

    /// Enregistrer sous : nouveau fichier, qui devient le fichier chargé.
    func saveAs(name: String, details: String, tags: [String]) {
        guard image.isComplete else { errorMessage = L("Le set n'est pas complet : relisez le HPD-15."); return }
        let n = name.trimmingCharacters(in: .whitespaces).isEmpty ? L("Sans titre") : name
        let s = StoredSet.make(from: image, name: n, details: details, tags: tags,
                               origin: loadedEntry?.item.origin ?? origin, catalog: catalog)
        do {
            let e = try library.add(s)
            // Le nom envoyé à l'appareil suit celui du fichier (10 caractères).
            setName(n)
            loadedEntryID = e.id
            origin = Lf("Fichier « %@ »", e.item.name)
            dirty = false
        } catch {
            errorMessage = Lf("Enregistrement : %@", error.localizedDescription)
        }
    }

    /// Envoie un set de la bibliothèque dans le patch temporaire du HPD-15, puis relit et compare.
    func sendToDevice(_ e: LibraryStore.Entry) {
        guard let img = e.item.image else {
            errorMessage = Lf("Le fichier « %@ » est incomplet ou abîmé.", e.url.lastPathComponent)
            return
        }
        sendImage(img, name: e.item.name, entry: e.id, origin: Lf("Fichier « %@ »", e.item.name), stillDirty: false)
    }

    /// Renvoie au HPD-15 le set affiché (après un changement de patch fait sur l'appareil).
    func resendCurrentSet() {
        guard image.isComplete else { return }
        sendImage(image, name: image.name ?? "set", entry: loadedEntryID, origin: origin, stillDirty: true)
    }

    /// Écrit une image complète dans le patch temporaire, relit et compare.
    private func sendImage(_ img: PatchImage, name: String, entry: UUID?, origin: String, stillDirty: Bool) {
        run(Lf("Envoi de « %@ »", name)) {
            if self.padChannel == nil || !self.deviceFound { try await self.readPadChannel() }
            // Ordre de la carte : Pad Sets d'abord, puis zones, effets, LFO, COMMON.
            var pending = PatchMap.blocks
            var mismatch: [String] = []
            var back = PatchImage()
            for pass in 0..<2 {
                for (i, b) in pending.enumerated() {
                    self.progress = Lf("Envoi de « %@ »… %d/%d", name, i + 1, pending.count) + (pass > 0 ? L(" (2e passage)") : "")
                    guard let data = img.range(b.offset, b.size) else { continue }
                    if Self.isPadSet(b.offset) {
                        // Instrument du Pad Set (octets 00-01) jamais envoyé : l'écrire applique ses 5 sons
                        // à toute la rangée (observé le 2026-11-14), et le HPD-15 le recalcule de lui-même.
                        try await self.client.write(HPD15Map.tempPatch.adding(b.offset + 2), data: Array(data[2...]),
                                                    label: "DT1 \(b.name) (sans Inst)")
                    } else if pass > 0 && b.offset == PatchMap.effect {
                        // 2e passage des effets : seulement les octets qui diffèrent (le type, déjà juste, n'est pas
                        // réécrit : sa réécriture pourrait réinitialiser les paramètres de l'effet).
                        for run in Self.differingRuns(back.range(b.offset, b.size), data) {
                            try await self.client.write(HPD15Map.tempPatch.adding(b.offset + run.lowerBound),
                                                        data: Array(data[run]), label: "DT1 \(b.name) +\(run.lowerBound)")
                        }
                    } else {
                        try await self.client.write(HPD15Map.tempPatch.adding(b.offset), data: data, label: "DT1 \(b.name)")
                    }
                }
                await self.pause(300)
                self.progress = L("Vérification…")
                back = try await self.dumpTemporaryPatch()
                mismatch = PatchMap.blocks.filter { !Self.sameBlock(back, img, $0.offset, $0.size) }.map { $0.name }
                pending = PatchMap.blocks.filter { mismatch.contains($0.name) }
                if mismatch.isEmpty { break }
            }
            // On affiche ce que le HPD-15 contient réellement.
            self.adopt(back, origin: origin, entry: entry)
            self.dirty = stillDirty || !mismatch.isEmpty
            if !mismatch.isEmpty {
                let detail = mismatch.map { name -> String in
                    guard let b = PatchMap.blocks.first(where: { $0.name == name }),
                          let f = img.range(b.offset, b.size), let d = back.range(b.offset, b.size) else { return name }
                    let first = Self.isPadSet(b.offset) ? 2 : 0
                    let offs = (first..<b.size).filter { f[$0] != d[$0] }.map { String(format: "%02X", $0) }
                    return Lf("%@ (octets %@)", name, offs.joined(separator: " "))
                }
                self.notice = Lf("Envoyé, mais le HPD-15 n'a pas tout repris : %@. L'écran montre l'état réel de l'appareil.", detail.joined(separator: " ; "))
            }
        }
    }

    static func isPadSet(_ offset: Int) -> Bool { (0..<3).contains { PatchMap.padSet($0) == offset } }

    /// Comparaison d'un bloc, en ignorant l'instrument des Pad Sets (valeur recalculée par le HPD-15).
    static func sameBlock(_ a: PatchImage, _ b: PatchImage, _ offset: Int, _ size: Int) -> Bool {
        let first = isPadSet(offset) ? 2 : 0
        return a.range(offset + first, size - first) == b.range(offset + first, size - first)
    }

    /// Plages contiguës d'octets différents entre deux blocs.
    static func differingRuns(_ a: [UInt8]?, _ b: [UInt8]) -> [Range<Int>] {
        guard let a = a, a.count == b.count else { return [0..<b.count] }
        var runs: [Range<Int>] = []
        var start: Int?
        for i in 0..<b.count {
            if a[i] != b[i] { if start == nil { start = i } }
            else if let s = start { runs.append(s..<i); start = nil }
        }
        if let s = start { runs.append(s..<b.count) }
        return runs
    }

    /// Met à jour les informations (nom, description, étiquettes) d'un fichier sans toucher au son.
    func updateInfo(_ e: LibraryStore.Entry, name: String, details: String, tags: [String]) {
        var s = e.item
        s.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? e.item.name : name
        s.details = details
        s.tags = tags
        if let img = e.item.image {
            s = StoredSet.make(from: img, name: s.name, details: details, tags: tags, origin: e.item.origin,
                               catalog: catalog, id: e.item.id, created: e.item.created)
        }
        do { _ = try library.update(e, with: s) } catch { errorMessage = error.localizedDescription }
    }

    /// Relit le set en cours sur le HPD-15. Si un fichier est chargé, il le reste :
    /// le set est marqué « modifié » s'il diffère du fichier (réglage fait sur l'appareil, par exemple).
    func readFromDevice() {
        run(L("Lecture du HPD-15")) {
            if self.padChannel == nil || !self.deviceFound { try await self.readPadChannel() }
            let img = try await self.dumpTemporaryPatch()
            if let e = self.loadedEntry {
                self.adopt(img, origin: Lf("Fichier « %@ »", e.item.name), entry: e.id)
                self.dirty = e.item.image.map { f in PatchMap.blocks.contains { !Self.sameBlock(f, img, $0.offset, $0.size) } } ?? true
            } else {
                self.adopt(img, origin: L("HPD-15 (patch en cours)"))
            }
        }
    }

    /// Charge un preset (P…) ou une mémoire User (U…) sur le HPD-15, puis le lit comme base.
    func loadPatch(code: String) {
        guard let p = catalog?.patch(code: code) else { return }
        if dirty {
            // Le set modifié n'est pas perdu tant qu'il est dans un fichier ; ici on le note seulement.
            log(HPDLogEntry(.info, Lf("Modifications non enregistrées abandonnées (%@).", image.name ?? "set")))
        }
        run(Lf("Chargement de %@", code)) {
            if self.padChannel == nil { try await self.readPadChannel() }
            guard let ch = self.padChannel else { throw HPDError.invalid(L("canal des pads sur OFF dans le HPD-15.")) }
            self.ownProgramChange = (p.bankMSB, p.pc, Date())
            try await self.client.sendRaw(MIDIMessage.bankProgram(channel: ch, msb: p.bankMSB, program: p.pc), label: "Bank/PC \(code)")
            await self.pause(1000)                       // le HPD-15 change de patch
            let img = try await self.dumpTemporaryPatch()
            let label = code.hasPrefix("P") ? "\(code) \(p.name)" : "\(code) \(img.name ?? "")"
            self.adopt(img, origin: label)
        }
    }

    // MARK: - Modifications (envoyées au patch temporaire, temporisées)

    func setInstrument(_ value: Int, for z: Zone) {
        writeZone(z, offset: PatchMap.ZoneParam.inst, bytes: Nibble.encode(value, count: 4))
    }

    func setParam(_ p: ZoneParam, _ v: Int, for z: Zone) {
        writeZone(z, offset: p.offset, bytes: p.encode(v))
    }

    func setName(_ name: String) {
        let b = PatchImage.nameBytes(name)
        let off = PatchMap.common + PatchMap.CommonParam.name
        guard image.range(off, b.count) != b else { return }
        image.set(off, b)
        dirty = true
        scheduleWrite(offset: off, count: b.count)
    }

    func setMasterVolume(_ v: Int) {
        let off = PatchMap.common + PatchMap.CommonParam.masterVolume
        image.set(off, [UInt8(max(0, min(127, v)))])
        dirty = true
        scheduleWrite(offset: off, count: 1)
    }

    // MARK: - Effets du set (bloc EFFECT + COMMON 08)

    func effectByte(_ off: Int) -> Int? { image.byte(PatchMap.effect + off).map { Int($0) } }

    var multiEffectsOn: Bool { image.byte(PatchMap.common + PatchMap.CommonParam.multiEffects) == 1 }

    func setMultiEffects(_ on: Bool) {
        let off = PatchMap.common + PatchMap.CommonParam.multiEffects
        image.set(off, [on ? 1 : 0])
        dirty = true
        scheduleWrite(offset: off, count: 1)
    }

    /// Écrit un octet du bloc EFFECT. Après un changement de type, relit le bloc pour voir
    /// ce que le HPD-15 a reconfiguré (algorithme, paramètres).
    func setEffect(_ param: Int, _ v: Int) {
        let off = PatchMap.effect + param
        let byte = UInt8(max(0, min(127, v)))
        guard image.byte(off) != byte else { return }
        image.set(off, [byte])
        dirty = true
        scheduleWrite(offset: off, count: 1)
        if param == PatchMap.EffectParam.reverbType || param == PatchMap.EffectParam.mfxType {
            rereadEffects()
        }
    }

    /// Fait passer (ou non) toutes les zones par le multi-effet.
    func setAllZonesMFX(_ on: Bool) {
        for z in Zone.allCases { setParam(.mfx, on ? 1 : 0, for: z) }
    }

    private var rereadToken = 0

    /// Relecture du bloc EFFECT 0,8 s après le dernier changement de type.
    private func rereadEffects() {
        rereadToken += 1
        let token = rereadToken
        Task { @MainActor in
            await self.pause(800)
            guard token == self.rereadToken, !self.busy else { return }
            while !self.writers.isEmpty { await self.pause(50) }
            if let d = try? await self.client.readExact(HPD15Map.tempPatch.adding(PatchMap.effect),
                                                        size: PatchMap.effectSize, label: "EFFECT (relecture)", retries: 2) {
                self.image.set(PatchMap.effect, d)
            }
        }
    }

    /// Type de réverbération du set (0 = OFF ; nil si non lu).
    var reverbType: Int? { image.byte(PatchMap.effect + PatchMap.EffectParam.reverbType).map { Int($0) } }

    var masterVolume: Int { Int(image.byte(PatchMap.common + PatchMap.CommonParam.masterVolume) ?? 100) }

    private func writeZone(_ z: Zone, offset: Int, bytes: [UInt8]) {
        let off = PatchMap.zone(z) + offset
        guard image.has(PatchMap.zone(z), PatchMap.zoneSize) else { return }
        if image.range(off, bytes.count) == bytes { return }
        image.set(off, bytes)
        dirty = true
        scheduleWrite(offset: off, count: bytes.count)
    }

    /// Une seule tâche par adresse : elle écrit la dernière valeur (glissement de curseur).
    private func scheduleWrite(offset: Int, count: Int) {
        pendingWrites[offset] = count
        guard !writers.contains(offset), connected else { return }
        writers.insert(offset)
        Task { @MainActor in
            while let n = self.pendingWrites.removeValue(forKey: offset) {
                await self.pause(50)
                guard let data = self.image.range(offset, n) else { continue }
                do {
                    try await self.client.write(HPD15Map.tempPatch.adding(offset), data: data, label: "DT1")
                } catch {
                    self.errorMessage = Lf("Écriture : %@", error.localizedDescription)
                }
            }
            self.writers.remove(offset)
        }
    }

    // MARK: - Écoute d'une zone depuis le Mac

    /// Fait sonner la zone sélectionnée par le HPD-15 (Note On sur le canal des pads).
    func audition(_ z: Zone) {
        guard let ch = padChannel, let s = image.zone(z), s.midiNoteRaw <= 127 else { return }
        let note = s.midiNoteRaw
        Task { @MainActor in
            try? await self.client.sendRaw(MIDIMessage.noteOn(channel: ch, note: note, velocity: 100), label: "Note On")
            await self.pause(400)
            try? await self.client.sendRaw(MIDIMessage.noteOff(channel: ch, note: note), label: "Note Off")
        }
    }

    // MARK: - Frappe sur l'appareil → sélection

    private func handleChannel(_ m: [UInt8]) {
        if let ch = padChannel, Int(m[0] & 0x0F) + 1 != ch { return }
        switch m[0] & 0xF0 {
        case 0x90 where m.count == 3 && m[2] > 0:
            guard let z = noteMap[Int(m[1])] else { return }
            selectedZone = z
            flash(z)
        case 0xB0 where m.count == 3 && m[1] == 0:
            lastBankMSB = Int(m[2])                     // Bank Select MSB émis par le HPD-15
        case 0xC0 where m.count == 2:
            deviceProgramChange(msb: lastBankMSB, pc: Int(m[1]))
        default:
            break
        }
    }

    // MARK: - Changement de patch fait sur le HPD-15 lui-même

    /// Le HPD-15 a changé de patch et le set affiché n'était pas enregistré : code du nouveau patch.
    @Published var devicePatchChange: String?
    private var lastBankMSB = 0
    private var ownProgramChange: (msb: Int, pc: Int, date: Date)?
    private var patchChangeToken = 0

    /// Code P…/U… d'après Bank MSB + Program Change (MIDI Implementation p. 101).
    func patchCode(msb: Int, pc: Int) -> String {
        if msb == 0 { return String(format: "U%02d%02d", pc / 8 + 1, pc % 8 + 1) }
        return catalog?.presetPatches.first(where: { $0.bankMSB == msb && $0.pc == pc })?.code ?? Lf("banque %d n° %d", msb + 1, pc + 1)
    }

    private func deviceProgramChange(msb: Int, pc: Int) {
        // Écho de notre propre changement (Soft Thru) : ignoré.
        if let own = ownProgramChange, own.msb == msb, own.pc == pc, Date().timeIntervalSince(own.date) < 3 { return }
        guard !busy else { return }
        let code = patchCode(msb: msb, pc: pc)
        log(HPDLogEntry(.info, Lf("Le HPD-15 est passé sur %@.", code)))
        // On attend que l'utilisateur ait fini de tourner la molette.
        patchChangeToken += 1
        let token = patchChangeToken
        Task { @MainActor in
            await self.pause(700)
            guard token == self.patchChangeToken, !self.busy else { return }
            if self.dirty && !self.image.bytes.isEmpty {
                self.devicePatchChange = code
            } else {
                self.readDevicePatch(code)
            }
        }
    }

    /// Lit le patch choisi sur l'appareil ; il devient la base du set (plus de fichier associé).
    func readDevicePatch(_ code: String) {
        devicePatchChange = nil
        run(Lf("Lecture de %@", code)) {
            let img = try await self.dumpTemporaryPatch()
            let name = code.hasPrefix("P") ? (self.catalog?.patch(code: code)?.name ?? "") : (img.name ?? "")
            self.adopt(img, origin: "\(code) \(name)")
        }
    }

    func flash(_ z: Zone) {
        flashZone = z
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            if !Task.isCancelled { self.flashZone = nil }
        }
    }

    // MARK: - Journal

    private func log(_ e: HPDLogEntry) {
        journal.append(LogLine(time: clock.string(from: e.date), direction: e.direction, text: e.text))
    }

    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(journal.lines.map { $0.plain }.joined(separator: "\n"), forType: .string)
    }

    func clearLog() { journal.lines.removeAll() }
}
