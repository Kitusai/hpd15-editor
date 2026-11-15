import Foundation
import AppKit
import HPD15Core

/// Résumé d'une zone, pour l'affichage et la recherche sans décoder les blocs.
struct ZoneBrief: Codable, Equatable {
    var zone: String
    var code: String
    var sound: String
}

/// Set enregistré dans un fichier `.hpdset` (JSON) sur le Mac.
struct StoredSet: Codable, Identifiable, Equatable {
    var formatVersion = 1
    var id = UUID()
    var name: String
    var details: String
    var tags: [String]
    var created: Date
    var modified: Date
    /// D'où vient le set : « P0101 Conga », « U0305 », « HPD-15 (patch en cours) »…
    var origin: String
    var zones: [ZoneBrief]
    var reverb: String
    var multiEffect: String
    /// Les 27 blocs du patch (noms de PatchMap.blocks) → octets en hexadécimal.
    var blocks: [String: String]

    enum CodingKeys: String, CodingKey {
        case formatVersion, id, name, details = "description", tags, created, modified, origin, zones, reverb, multiEffect, blocks
    }

    /// Image du patch reconstituée à partir des blocs (nil si un bloc manque ou est illisible).
    var image: PatchImage? {
        var img = PatchImage()
        for b in PatchMap.blocks {
            guard let h = blocks[b.name], let bytes = bytesFromHex(h), bytes.count == b.size else { return nil }
            img.set(b.offset, bytes)
        }
        return img
    }

    /// Construit un set à partir d'une image complète. Le nom de l'appareil (10 caractères) suit le nom du set.
    static func make(from source: PatchImage, name: String, details: String, tags: [String], origin: String,
                     catalog: HPD15Catalog?, id: UUID = UUID(), created: Date = Date()) -> StoredSet {
        var img = source
        img.set(PatchMap.common + PatchMap.CommonParam.name, PatchImage.nameBytes(name))
        var blocks: [String: String] = [:]
        for b in PatchMap.blocks {
            if let r = img.range(b.offset, b.size) { blocks[b.name] = r.hex }
        }
        let zones: [ZoneBrief] = Zone.allCases.compactMap { z in
            guard let s = img.zone(z) else { return nil }
            let i = catalog?.instrument(s.inst)
            return ZoneBrief(zone: z.rawValue, code: i?.code ?? "\(s.inst)", sound: i?.name ?? Lf("Son %d", s.inst))
        }
        let rt = Int(img.byte(PatchMap.effect + PatchMap.EffectParam.reverbType) ?? 0)
        let mt = Int(img.byte(PatchMap.effect + PatchMap.EffectParam.mfxType) ?? 0)
        let mon = img.byte(PatchMap.common + PatchMap.CommonParam.multiEffects) == 1
        return StoredSet(id: id, name: name, details: details, tags: tags, created: created, modified: Date(),
                         origin: origin, zones: zones,
                         reverb: PatchMap.reverbTypeName(rt),
                         multiEffect: PatchMap.mfxTypeName(mt) + (mon ? "" : L(" (désactivé)")),
                         blocks: blocks)
    }
}

/// Lit une chaîne hexadécimale (deux chiffres par octet, séparateurs libres).
func bytesFromHex(_ text: String) -> [UInt8]? {
    let digits = Array(text.filter { $0.isHexDigit })
    guard digits.count % 2 == 0 else { return nil }
    var out: [UInt8] = []
    out.reserveCapacity(digits.count / 2)
    var i = 0
    while i < digits.count {
        guard let b = UInt8(String(digits[i...(i + 1)]), radix: 16) else { return nil }
        out.append(b)
        i += 2
    }
    return out
}

/// Dossier de sets sur le Mac (choisi par l'utilisateur, mémorisé).
@MainActor
final class LibraryStore: ObservableObject {
    struct Entry: Identifiable, Equatable {
        var url: URL
        var item: StoredSet
        var id: UUID { item.id }
    }

    static let fileExtension = "hpdset"

    @Published var entries: [Entry] = []
    @Published var folder: URL
    @Published var problem: String?

    private let fm = FileManager.default

    init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        folder = UserDefaults.standard.string(forKey: "libraryPath").map { URL(fileURLWithPath: $0) }
            ?? docs.appendingPathComponent("Editeur HPD15 Sets")
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        reload()
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func reload() {
        problem = nil
        let urls = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var out: [Entry] = []
        var bad: [String] = []
        for u in urls where u.pathExtension.lowercased() == Self.fileExtension {
            if let data = try? Data(contentsOf: u), let item = try? decoder.decode(StoredSet.self, from: data) {
                out.append(Entry(url: u, item: item))
            } else {
                bad.append(u.lastPathComponent)
            }
        }
        if !bad.isEmpty { problem = Lf("Fichier(s) illisible(s) ignoré(s) : %@", bad.joined(separator: ", ")) }
        entries = out.sorted { $0.item.name.localizedCaseInsensitiveCompare($1.item.name) == .orderedAscending }
    }

    func entry(_ id: UUID?) -> Entry? { entries.first { $0.id == id } }

    private func safeName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\?*\"<>|")
        let t = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Set" : t
    }

    private func uniqueURL(for name: String, excluding: URL? = nil) -> URL {
        let base = safeName(name)
        var url = folder.appendingPathComponent(base).appendingPathExtension(Self.fileExtension)
        var i = 2
        while fm.fileExists(atPath: url.path), url != excluding {
            url = folder.appendingPathComponent("\(base) \(i)").appendingPathExtension(Self.fileExtension)
            i += 1
        }
        return url
    }

    /// Nouveau fichier.
    @discardableResult
    func add(_ s: StoredSet) throws -> Entry {
        let url = uniqueURL(for: s.name)
        try encoder.encode(s).write(to: url, options: .atomic)
        reload()
        return entries.first(where: { $0.id == s.id }) ?? Entry(url: url, item: s)
    }

    /// Écrase un fichier existant (renomme le fichier si le nom du set a changé).
    @discardableResult
    func update(_ e: Entry, with s: StoredSet) throws -> Entry {
        var ns = s
        ns.modified = Date()
        var target = e.url
        if safeName(ns.name) != safeName(e.item.name) { target = uniqueURL(for: ns.name, excluding: e.url) }
        try encoder.encode(ns).write(to: target, options: .atomic)
        if target != e.url { try? fm.trashItem(at: e.url, resultingItemURL: nil) }
        reload()
        return entries.first(where: { $0.id == ns.id }) ?? Entry(url: target, item: ns)
    }

    func duplicate(_ e: Entry) throws {
        var s = e.item
        s.id = UUID()
        s.name += L(" copie")
        s.created = Date()
        s.modified = Date()
        try add(s)
    }

    func trash(_ e: Entry) {
        do { try fm.trashItem(at: e.url, resultingItemURL: nil) } catch { problem = error.localizedDescription }
        reload()
    }

    func reveal(_ e: Entry) { NSWorkspace.shared.activateFileViewerSelecting([e.url]) }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.prompt = L("Choisir")
        if panel.runModal() == .OK, let url = panel.url {
            folder = url
            UserDefaults.standard.set(url.path, forKey: "libraryPath")
            reload()
        }
    }
}
