import Foundation

/// Carte d'adresses du HPD-15 (MIDI Implementation p. 104-108).
public enum HPD15Map {
    // Blocs principaux
    public static let system = HPDAddress(0x00, 0x00, 0x00, 0x00)
    public static let tempPatch = HPDAddress(0x01, 0x00, 0x00, 0x00)
    public static let systemBulk = HPDAddress(0x10, 0x00, 0x00, 0x00)
    public static let tempPatchBulk = HPDAddress(0x11, 0x00, 0x00, 0x00)
    public static let userPatternsBulk = HPDAddress(0x20, 0x00, 0x00, 0x00)

    /// Patch utilisateur U0101…U1008 : index 0…79.
    public static func userPatchBulk(_ index: Int) -> HPDAddress {
        HPDAddress(0x12, UInt8(index & 0x7F), 0x00, 0x00)
    }

    // Tailles des requêtes de dump (p. 108)
    public static let dumpSizeSystem = HPDAddress(0x01, 0x00, 0x00, 0x00)
    public static let dumpSizeTempPatch = HPDAddress(0x01, 0x00, 0x00, 0x00)
    public static let dumpSizeUserPatch = HPDAddress(0x00, 0x01, 0x00, 0x00)
    public static let dumpSizeZero = HPDAddress(0x00, 0x00, 0x00, 0x00)

    // Système (offsets sous 00 00 00 00)
    public static let systemMIDI = system.adding(0x02 << 14)          // 00 02 00 00
    public static let systemMIDISize = 0x07
    public enum SystemMIDIParam {
        public static let padChannel = 0x04          // 0-15 = canal 1-16, 16 = OFF
    }
}

/// Zones jouables d'un patch, dans l'ordre de la carte d'adresses.
public enum Zone: String, CaseIterable, Codable, Identifiable {
    case a1 = "A1", a2 = "A2", a3 = "A3", a4 = "A4", a5 = "A5"
    case b1 = "B1", b2 = "B2", b3 = "B3", b4 = "B4", b5 = "B5"
    case c1 = "C1", c2 = "C2", c3 = "C3", c4 = "C4", c5 = "C5"
    case pedal = "PEDAL", dBeam = "D BEAM", ribbonL = "RIBBON L", ribbonR = "RIBBON R"
    case trig1 = "TRIG 1", trig2 = "TRIG 2"

    public var id: String { rawValue }

    /// Octet haut de l'offset dans le patch (« 10 00 » pour A1, etc.).
    public var blockHigh: Int {
        switch self {
        case .a1: return 0x10
        case .a2: return 0x11
        case .a3: return 0x12
        case .a4: return 0x13
        case .a5: return 0x14
        case .b1: return 0x15
        case .b2: return 0x16
        case .b3: return 0x17
        case .b4: return 0x18
        case .b5: return 0x19
        case .c1: return 0x1A
        case .c2: return 0x1B
        case .c3: return 0x1C
        case .c4: return 0x1D
        case .c5: return 0x1E
        case .pedal: return 0x1F
        case .dBeam: return 0x20
        case .ribbonL: return 0x21
        case .ribbonR: return 0x22
        case .trig1: return 0x23
        case .trig2: return 0x24
        }
    }

    public var isPad: Bool { blockHigh <= 0x1E }
    public var isController: Bool { (0x1F...0x22).contains(blockHigh) }
}

/// Offsets et tailles dans un patch (temporaire ou utilisateur).
public enum PatchMap {
    public static let padSetSize = 0x0C
    public static let zoneSize = 0x2B
    public static let effectSize = 0x18
    public static let lfoSize = 0x08
    public static let commonSize = 0x15

    public static func padSet(_ i: Int) -> Int { off(i, 0) }          // 00 00, 01 00, 02 00
    public static func zone(_ z: Zone) -> Int { off(z.blockHigh, 0) }
    public static let effect = off(0x30, 0)
    public static let lfo = off(0x38, 0)
    public static let common = off(0x40, 0)

    /// Tous les sous-blocs d'un patch : (nom, offset, taille).
    public static var blocks: [(name: String, offset: Int, size: Int)] {
        var b: [(String, Int, Int)] = []
        for (i, n) in ["PAD SET A", "PAD SET B", "PAD SET C"].enumerated() { b.append((n, padSet(i), padSetSize)) }
        for z in Zone.allCases { b.append((z.rawValue, zone(z), zoneSize)) }
        b.append(("EFFECT", effect, effectSize))
        b.append(("LFO", lfo, lfoSize))
        b.append(("COMMON", common, commonSize))
        return b
    }

    public enum ZoneParam {
        public static let inst = 0x00          // 4 octets nibblés, 0-600 (PEDAL 0-615)
        public static let pitch = 0x04         // 4 octets nibblés, 0-4800 (2400 = 0 cent)
        public static let level = 0x08
        public static let pan = 0x09           // 2 octets nibblés, 1-129 (64 = centre)
        public static let decay = 0x0B         // 0-62 (31 = 0)
        public static let sweep = 0x0C
        public static let color = 0x0D
        public static let reverbSend = 0x0E
        public static let mfxSwitch = 0x0F     // le pad passe (ou non) par le M-FX du patch
        public static let triggerMode = 0x10
        public static let velocityCurve = 0x11
        public static let midiNote = 0x23      // 2 octets nibblés, 0-128
    }

    public enum EffectParam {
        public static let reverbType = 0x00
        public static let reverbAlgorithm = 0x02
        public static let reverbLevel = 0x03
        public static let reverbTime = 0x04
        public static let reverbHFDamp = 0x05
        public static let delayFeedback = 0x06
        public static let mfxType = 0x07
        public static let mfxDepth = 0x08
        public static let mfxAlgorithm = 0x09
        public static let mfxOutput = 0x0A
        public static let mfxReverbSend = 0x0B
    }

    /// Types de réverbération/délai, dans l'ordre du manuel (p. 95).
    /// **Valeur stockée = rang + 1** (validé le 2026-11-14 : 1 = OFF, 2 = WarmRoom, 3 = DarkRoom à l'écran du HPD-15).
    /// La valeur 0 (P0101 Conga) se comporte aussi comme OFF. Utiliser `reverbTypeName(_:)`.
    public static func reverbTypeName(_ value: Int) -> String {
        if value == 0 { return "OFF" }
        return reverbTypeNames.indices.contains(value - 1) ? reverbTypeNames[value - 1] : "(\(value))"
    }

    /// Réverbération coupée (valeurs 0 et 1).
    public static func reverbIsOff(_ value: Int) -> Bool { value <= 1 }

    public static let reverbTypeNames = [
        "OFF", "WarmRoom", "DarkRoom", "BrightRoom", "Club", "GymStage", "Underground", "ThinPlate", "ThickPlate",
        "EmptyHall", "BigTube", "RichAmb", "ShortDelay", "MedDelay", "LongDelay", "PanDelaySht", "PanDelayMed", "PanDelayLng"
    ]

    /// Types de multi-effet, dans l'ordre du manuel (p. 95-96).
    /// **Valeur stockée = rang dans cette liste + 1** (validé le 2026-11-14 : 80 = Hall A et 74 = 4TempoDly à l'écran
    /// du HPD-15). Utiliser `mfxTypeName(_:)`.
    public static func mfxTypeName(_ value: Int) -> String {
        mfxTypeNames.indices.contains(value - 1) ? mfxTypeNames[value - 1] : "(\(value))"
    }

    public static let mfxTypeNames = [
        "Low Boost", "Low Cut", "Mid Boost", "Mid Cut", "High Boost", "High Cut", "Limiter", "Compressor", "ComPRESSED!",
        "Enhancer", "Radio", "OnAir", "TiledRoom", "Outside", "NoHighs", "Only Lows", "Only Mids", "Only Highs",
        "DynamicFltr", "Ctrl Wah", "Sustainer", "RadioOD", "SmallOD", "BigOD", "LoudOD", "RadioDST", "SmallDST", "BigDST",
        "LoudDST", "Lo-Fi", "Lo-Fi(mono)", "RingModltr", "Bell", "Buzz", "MetalBar", "Stereo Cho", "Glossy Cho",
        "Phasy Cho", "TetraChorus", "Bamboo Cho", "TremoloCho", "Giddy Cho", "Sigh Cho", "Space D", "Stereo Fln",
        "Wind Fln", "Grumble Fln", "Jet Fln", "StepFlanger", "AnalogCyber", "Phaser", "Rubbing", "Arpeggio", "Warp",
        "Bandit", "PitchShift", "StereoDelay", "Doubling", "Booming", "RhythmDly1", "RhythmDly2", "Mod Delay",
        "CrossModDly", "TimeCtrlDly", "3TapDlySht", "3RhythmSht", "3TapDlyLng", "3RhythmLng", "3TempoDly", "4TapDlySht",
        "4RhythmSht", "4TapDlyLng", "4RhythmLng", "4TempoDly", "SoftRoom", "HardRoom", "RoomCorner", "Stage", "Plate",
        "Hall A", "Hall B", "Tunnel", "Stadium", "GateReverb", "ReverseGate"
    ]

    /// Algorithmes du multi-effet (offset 09, fixé par le type).
    public static let mfxAlgorithmNames = [
        "Stereo EQ", "CompLimiter", "Enhancer", "Spectrum", "Isolator", "DynamicFltr", "Sustainer", "Overdrive",
        "Distortion", "Lo-Fi", "RingModltr", "Stereo Cho", "TetraChorus", "TremoloCho", "Space D", "Stereo Fln",
        "StepFlanger", "Phaser", "FbackPitch", "StereoDelay", "Mod Delay", "TimeCtrlDly", "3TapDlySht", "3TapDlyLng",
        "4TapDlySht", "4TapDlyLng", "AdvanceRev", "GateReverb"
    ]

    /// Algorithmes de réverbération (offset 02, fixé par le type).
    public static let reverbAlgorithmNames = ["OFF", "Room1", "Room2", "Stage", "Plate", "Hall1", "Hall2", "Delay", "PanDly"]

    /// Atténuation des aigus de la réverbération (offset 05).
    public static let hfDampNames = ["200 Hz", "250 Hz", "315 Hz", "400 Hz", "500 Hz", "630 Hz", "800 Hz", "1 kHz", "1,25 kHz",
                                     "1,6 kHz", "2 kHz", "2,5 kHz", "3,15 kHz", "4 kHz", "5 kHz", "6,3 kHz", "8 kHz", "THRU"]

    public enum CommonParam {
        public static let masterVolume = 0x00
        public static let multiEffects = 0x08
        public static let name = 0x0B          // 10 caractères ASCII 32-127
        public static let nameLength = 10
    }
}

/// Image mémoire d'un patch : octet par offset relatif, quelle que soit l'origine
/// (dump bulk, lectures individuelles, fichier). Les octets jamais reçus restent absents.
public struct PatchImage: Equatable {
    public private(set) var bytes: [Int: UInt8] = [:]

    public init() {}

    /// Range les DT1 reçus. `base` = adresse du patch (01 00 00 00, 11 00 00 00, 12 mm 00 00).
    /// Les trames hors de la plage du patch sont ignorées ; renvoie le nombre d'octets rangés.
    @discardableResult
    public mutating func absorb(address: HPDAddress, data: [UInt8], base: HPDAddress) -> Int {
        let rel = address.value - base.value
        guard rel >= 0, rel < off(0x41, 0) else { return 0 }
        for (i, b) in data.enumerated() { bytes[rel + i] = b }
        return data.count
    }

    public mutating func set(_ offset: Int, _ data: [UInt8]) {
        for (i, b) in data.enumerated() { bytes[offset + i] = b }
    }

    public func byte(_ offset: Int) -> UInt8? { bytes[offset] }

    public func range(_ offset: Int, _ count: Int) -> [UInt8]? {
        var out: [UInt8] = []
        for i in 0..<count {
            guard let b = bytes[offset + i] else { return nil }
            out.append(b)
        }
        return out
    }

    public func has(_ offset: Int, _ count: Int) -> Bool { range(offset, count) != nil }

    public var name: String? {
        guard let r = range(PatchMap.common + PatchMap.CommonParam.name, PatchMap.CommonParam.nameLength) else { return nil }
        return String(bytes: r.map { (32...126).contains($0) ? $0 : 0x20 }, encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces)
    }

    /// Tous les sous-blocs du patch sont présents.
    public var isComplete: Bool { PatchMap.blocks.allSatisfy { has($0.offset, $0.size) } }

    public var missingBlocks: [String] { PatchMap.blocks.filter { !has($0.offset, $0.size) }.map { $0.name } }

    /// Octets du nom (10 caractères ASCII imprimables, complétés par des espaces).
    public static func nameBytes(_ name: String) -> [UInt8] {
        var b = Array(name.unicodeScalars.compactMap { $0.value >= 32 && $0.value <= 126 ? UInt8($0.value) : nil }
            .prefix(PatchMap.CommonParam.nameLength))
        while b.count < PatchMap.CommonParam.nameLength { b.append(0x20) }
        return b
    }

    /// Table note MIDI → zone, d'après les notes du patch (validé le 2026-11-14 : valeur = n° de note).
    /// Les rubans émettent aussi « leur note − 3 » selon le sens du geste (observé : 56 et 75).
    public var noteMap: [Int: Zone] {
        var map: [Int: Zone] = [:]
        for z in Zone.allCases {
            guard let s = zone(z), s.midiNoteRaw <= 127 else { continue }
            if map[s.midiNoteRaw] == nil { map[s.midiNoteRaw] = z }
        }
        for z in [Zone.ribbonL, .ribbonR] {
            if let s = zone(z), s.midiNoteRaw >= 3, s.midiNoteRaw <= 127, map[s.midiNoteRaw - 3] == nil {
                map[s.midiNoteRaw - 3] = z
            }
        }
        return map
    }

    /// Lecture d'une zone (nil si le bloc n'a pas été reçu).
    public func zone(_ z: Zone) -> ZoneState? {
        guard let r = range(PatchMap.zone(z), PatchMap.zoneSize) else { return nil }
        return ZoneState(zone: z, bytes: r)
    }
}

/// Paramètres principaux d'une zone, décodés.
public struct ZoneState: Equatable {
    public let zone: Zone
    public let raw: [UInt8]

    public init(zone: Zone, bytes: [UInt8]) {
        self.zone = zone
        self.raw = bytes
    }

    typealias P = PatchMap.ZoneParam
    public var inst: Int { Nibble.decode(raw[P.inst..<(P.inst + 4)]) }
    public var pitchCents: Int { Nibble.decode(raw[P.pitch..<(P.pitch + 4)]) - 2400 }
    public var level: Int { Int(raw[P.level]) }
    public var pan: Int { Nibble.decode(raw[P.pan..<(P.pan + 2)]) }
    public var decay: Int { Int(raw[P.decay]) - 31 }
    public var sweep: Int { Int(raw[P.sweep]) - 31 }
    public var color: Int { Int(raw[P.color]) - 31 }
    public var reverbSend: Int { Int(raw[P.reverbSend]) }
    public var mfx: Bool { raw[P.mfxSwitch] != 0 }
    public var midiNoteRaw: Int { Nibble.decode(raw[P.midiNote..<(P.midiNote + 2)]) }

    public var panText: String {
        switch pan {
        case 64: return "C"
        case 1..<64: return "L\(64 - pan)"
        case 65...127: return "R\(pan - 64)"
        case 128: return "Rnd"
        case 129: return "Alt"
        default: return "?\(pan)"
        }
    }
}
