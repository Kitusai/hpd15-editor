import Foundation

/// Catalogue extrait du manuel (p. 90-94) : instruments, Pad Set instruments, presets, mémoires User.
/// Ressource JSON modifiable (leçon SonicCell : une doc peut être fausse, il faut pouvoir corriger).
public struct HPD15Catalog: Codable {
    public struct Instrument: Codable, Identifiable {
        public let value: Int
        public let code: String
        public let name: String
        public let category: String
        public let flags: [String]
        public var id: Int { value }
    }
    public struct PadSetInstrument: Codable, Identifiable {
        public let value: Int
        public let number: Int
        public let name: String
        public var id: Int { value }
    }
    public struct PresetPatch: Codable, Identifiable {
        public let code: String
        public let group: Int
        public let groupName: String
        public let index: Int
        public let name: String
        public let bankMSB: Int
        public let pc: Int
        public var id: String { code }
    }
    public struct UserPatch: Codable, Identifiable {
        public let code: String
        public let bankMSB: Int
        public let pc: Int
        public var id: String { code }
        /// Index 0…79 pour l'adresse 12 mm 00 00.
        public var index: Int { pc }
    }

    public let instruments: [Instrument]
    public let padSetInstruments: [PadSetInstrument]
    public let presetPatches: [PresetPatch]
    public let userPatches: [UserPatch]

    /// Bundle des ressources du cœur : dans une application empaquetée, il est copié dans
    /// Contents/Resources ; sinon (swift run) on utilise Bundle.module.
    public static var resourceBundle: Bundle {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("EditeurHPD15_HPD15Core.bundle"),
           let b = Bundle(url: url) { return b }
        return Bundle.module
    }

    public static func load() throws -> HPD15Catalog {
        guard let url = resourceBundle.url(forResource: "catalog-hpd15", withExtension: "json") else {
            throw NSError(domain: "HPD15", code: 1, userInfo: [NSLocalizedDescriptionKey: "catalog-hpd15.json introuvable"])
        }
        return try JSONDecoder().decode(HPD15Catalog.self, from: Data(contentsOf: url))
    }

    public func instrument(_ value: Int) -> Instrument? {
        instruments.indices.contains(value) && instruments[value].value == value
            ? instruments[value] : instruments.first { $0.value == value }
    }

    /// Catégories dans l'ordre du manuel.
    public var categories: [String] {
        var out: [String] = []
        for i in instruments where !out.contains(i.category) { out.append(i.category) }
        return out
    }

    /// Groupes de presets dans l'ordre (1…10).
    public var presetGroups: [(id: Int, name: String, patches: [PresetPatch])] {
        let ids = Array(Set(presetPatches.map { $0.group })).sorted()
        var out: [(id: Int, name: String, patches: [PresetPatch])] = []
        for g in ids {
            let list = presetPatches.filter { $0.group == g }.sorted { $0.index < $1.index }
            out.append((id: g, name: list.first?.groupName ?? "", patches: list))
        }
        return out
    }

    /// "P0101", "U0305" (casse indifférente).
    public func patch(code: String) -> (bankMSB: Int, pc: Int, name: String)? {
        let c = code.uppercased()
        if let p = presetPatches.first(where: { $0.code == c }) { return (p.bankMSB, p.pc, p.name) }
        if let u = userPatches.first(where: { $0.code == c }) { return (u.bankMSB, u.pc, u.code) }
        return nil
    }
}
