import Foundation

/// Adresse (ou taille) Roland : 4 octets de 7 bits, soit une valeur de 28 bits.
/// Les offsets s'additionnent en base 128 (la doc les écrit « 7-bit hexadecimal »).
public struct HPDAddress: Hashable, Comparable, CustomStringConvertible {
    public let value: Int

    public init(value: Int) {
        precondition(value >= 0 && value < (1 << 28), "Adresse Roland hors limites : \(value)")
        self.value = value
    }

    public init(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) {
        self.value = (Int(a & 0x7F) << 21) | (Int(b & 0x7F) << 14) | (Int(c & 0x7F) << 7) | Int(d & 0x7F)
    }

    public init?(bytes: [UInt8]) {
        guard bytes.count == 4, bytes.allSatisfy({ $0 < 0x80 }) else { return nil }
        self.init(bytes[0], bytes[1], bytes[2], bytes[3])
    }

    public var bytes: [UInt8] {
        [UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F),
         UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F)]
    }

    /// Ajoute un offset exprimé en valeur linéaire (ex. `0x10 * 128 + 0x08` pour « 10 08 »).
    public func adding(_ offset: Int) -> HPDAddress { HPDAddress(value: value + offset) }

    public static func < (l: HPDAddress, r: HPDAddress) -> Bool { l.value < r.value }

    public var description: String { bytes.hex }
}

/// Offset « 7-bit hexadecimal » de la doc, ex. `off(0x10, 0x08)` pour « 10 08 ».
public func off(_ hi: Int, _ lo: Int) -> Int { hi * 128 + lo }

public extension Array where Element == UInt8 {
    /// "F0 41 10 ..."
    var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}

/// Valeurs « nibblées » (doc p. 108) : 4 bits utiles par octet, poids fort en premier.
public enum Nibble {
    public static func encode(_ value: Int, count: Int) -> [UInt8] {
        (0..<count).map { i in UInt8((value >> (4 * (count - 1 - i))) & 0x0F) }
    }
    public static func decode<C: Collection>(_ bytes: C) -> Int where C.Element == UInt8 {
        bytes.reduce(0) { ($0 << 4) | Int($1 & 0x0F) }
    }
}

/// Message SysEx décodé.
public enum HPDMessage: Equatable {
    case dt1(device: UInt8, address: HPDAddress, data: [UInt8])
    case identityReply(device: UInt8, payload: [UInt8])
    case other([UInt8])
    case invalid(String, [UInt8])
}

/// Trames Roland du HPD-15 (ID fabricant 41H, Model ID 00H 2EH — MIDI Implementation p. 100-104).
/// Attention : le Model ID tient sur 2 octets (3 pour le SonicCell).
public enum Roland {
    public static let manufacturerID: UInt8 = 0x41
    public static let modelID: [UInt8] = [0x00, 0x2E]
    public static let cmdRQ1: UInt8 = 0x11
    public static let cmdDT1: UInt8 = 0x12
    /// Index de l'octet de commande : F0 41 dev 00 2E cmd
    static let cmdIndex = 3 + modelID.count

    /// Checksum Roland (p. 109) : complément à 128 de la somme (adresse + données ou taille).
    public static func checksum(_ bytes: [UInt8]) -> UInt8 {
        let sum = bytes.reduce(0) { $0 + Int($1) }
        return UInt8((128 - (sum % 128)) & 0x7F)
    }

    /// Data Request 1. La taille est codée sur 4 octets de 7 bits.
    public static func rq1(device: UInt8, address: HPDAddress, size: HPDAddress) -> [UInt8] {
        let body = address.bytes + size.bytes
        return [0xF0, manufacturerID, device] + modelID + [cmdRQ1] + body + [checksum(body), 0xF7]
    }

    public static func rq1(device: UInt8, address: HPDAddress, size: Int) -> [UInt8] {
        rq1(device: device, address: address, size: HPDAddress(value: size))
    }

    /// Data Set 1.
    public static func dt1(device: UInt8, address: HPDAddress, data: [UInt8]) -> [UInt8] {
        let body = address.bytes + data
        return [0xF0, manufacturerID, device] + modelID + [cmdDT1] + body + [checksum(body), 0xF7]
    }

    /// Identity Request (Universal Non-realtime).
    public static func identityRequest(device: UInt8 = 0x7F) -> [UInt8] {
        [0xF0, 0x7E, device, 0x06, 0x01, 0xF7]
    }

    /// Décode une trame complète F0 … F7.
    public static func parse(_ f: [UInt8]) -> HPDMessage {
        guard f.count >= 3, f.first == 0xF0, f.last == 0xF7 else {
            return .invalid("trame incomplète", f)
        }
        // Identity Reply : F0 7E dev 06 02 41 2E 01 … F7
        if f.count >= 8, f[1] == 0x7E, f[3] == 0x06, f[4] == 0x02 {
            return .identityReply(device: f[2], payload: Array(f[5..<(f.count - 1)]))
        }
        // DT1 : F0 41 dev 00 2E 12 addr(4) data… sum F7  (au moins 1 octet de données)
        let c = cmdIndex
        if f.count >= c + 1 + 4 + 1 + 2, f[1] == manufacturerID,
           Array(f[3..<c]) == modelID, f[c] == cmdDT1 {
            let body = Array(f[(c + 1)..<(f.count - 2)])
            let sum = f[f.count - 2]
            guard checksum(body) == sum else {
                return .invalid("checksum incorrect (reçu \(String(format: "%02X", sum)), attendu \(String(format: "%02X", checksum(body))))", f)
            }
            guard let addr = HPDAddress(bytes: Array(body[0..<4])) else {
                return .invalid("adresse invalide", f)
            }
            return .dt1(device: f[2], address: addr, data: Array(body[4...]))
        }
        return .other(f)
    }
}

/// Événement MIDI reçu.
public enum MIDIEvent: Equatable {
    case sysex([UInt8])
    /// Message de canal complet (2 ou 3 octets, statut explicite même en « running status »).
    case channel([UInt8])
}

/// Découpe un flux d'octets MIDI en SysEx complets et messages de canal.
/// Ignore les messages temps réel (Active Sensing FEH, horloge…), même au milieu d'un SysEx.
public struct MIDIStreamParser {
    private var sysex: [UInt8] = []
    private var inSysEx = false
    private var running: UInt8 = 0
    private var pending: [UInt8] = []

    public init() {}

    private static func dataLength(_ status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0xC0, 0xD0: return 1
        default: return 2
        }
    }

    public mutating func feed(_ bytes: [UInt8]) -> [MIDIEvent] {
        var out: [MIDIEvent] = []
        for b in bytes {
            if b >= 0xF8 { continue }
            if b == 0xF0 {
                sysex = [0xF0]; inSysEx = true; running = 0; pending = []
                continue
            }
            if inSysEx {
                if b == 0xF7 {
                    sysex.append(0xF7); out.append(.sysex(sysex)); sysex = []; inSysEx = false
                    continue
                } else if b & 0x80 == 0 {
                    sysex.append(b); continue
                } else {
                    sysex = []; inSysEx = false       // SysEx interrompu : abandonné
                }
            }
            if b & 0x80 != 0 {
                if b >= 0x80 && b < 0xF0 { running = b; pending = [] } else { running = 0; pending = [] }
                continue
            }
            guard running != 0 else { continue }
            pending.append(b)
            if pending.count == Self.dataLength(running) {
                out.append(.channel([running] + pending))
                pending = []
            }
        }
        return out
    }
}

/// Messages MIDI de canal usuels (canal 1…16).
public enum MIDIMessage {
    public static func bankProgram(channel: Int, msb: Int, lsb: Int = 0, program: Int) -> [UInt8] {
        let ch = UInt8((channel - 1) & 0x0F)
        return [0xB0 | ch, 0x00, UInt8(msb & 0x7F),
                0xB0 | ch, 0x20, UInt8(lsb & 0x7F),
                0xC0 | ch, UInt8(program & 0x7F)]
    }
    public static func noteOn(channel: Int, note: Int, velocity: Int = 100) -> [UInt8] {
        [0x90 | UInt8((channel - 1) & 0x0F), UInt8(note & 0x7F), UInt8(velocity & 0x7F)]
    }
    public static func noteOff(channel: Int, note: Int) -> [UInt8] {
        [0x80 | UInt8((channel - 1) & 0x0F), UInt8(note & 0x7F), 0]
    }
}

/// Nom de note MIDI, convention Roland (60 = C4).
public func noteName(_ n: Int) -> String {
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return "\(names[((n % 12) + 12) % 12])\(n / 12 - 1)"
}
