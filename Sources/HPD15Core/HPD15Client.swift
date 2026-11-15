import Foundation

/// Transport MIDI abstrait (CoreMIDI en production, simulateur dans les vérifications).
public protocol SysExTransport: AnyObject {
    func send(_ bytes: [UInt8]) throws
}

public struct HPDLogEntry {
    public enum Direction: String { case tx = "TX", rx = "RX", info = "--", error = "!!" }
    public let date = Date()
    public let direction: Direction
    public let text: String
    public init(_ direction: Direction, _ text: String) {
        self.direction = direction
        self.text = text
    }
}

public enum HPDError: Error, LocalizedError {
    case busy
    case notConnected
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .busy: return "Une requête est déjà en cours."
        case .notConnected: return "Aucune sortie MIDI sélectionnée."
        case .invalid(let s): return s
        }
    }
}

/// Client HPD-15.
///
/// Principe : une requête = on envoie une trame puis on **capture** tout ce qui revient
/// jusqu'à un silence (le format exact des réponses bulk n'est pas décrit par la doc).
/// Les écritures DT1 sont découpées en paquets ≤ 128 octets et espacées d'au moins 40 ms (doc p. 104).
public final class HPD15Client {
    /// Device ID : 10H = « 17 » (réglage d'usine). 7FH = broadcast (Identity Request seulement).
    public var deviceByte: UInt8 = 0x10
    /// Écart minimal entre deux DT1 émis (doc : 40 ms ; marge incluse).
    public var dt1Interval: TimeInterval = 0.045
    /// Silence imposé après toute réception avant d'émettre quoi que ce soit.
    /// Mesuré le 2026-11-14 : tout message envoyé ≤ 30 ms après une réponse est ignoré
    /// par le HPD-15 (RQ1, DT1 et Program Change) ; dès 60 ms tout est traité (commande `cadence`).
    public var turnaround: TimeInterval = 0.1
    /// Nombre de renvois d'une requête restée sans aucune réponse.
    public var retries = 1
    public var onLog: ((HPDLogEntry) -> Void)?
    /// Messages de canal reçus (notes des pads, CC des rubans/D Beam…). Thread CoreMIDI.
    public var onChannelMessage: (([UInt8]) -> Void)?

    private let transport: SysExTransport
    private let lock = NSLock()
    private var parser = MIDIStreamParser()
    private var capture: Capture?
    private var lastDT1 = Date.distantPast
    private var lastRx = Date.distantPast

    /// Date de la dernière réception (hors messages temps réel).
    public var lastReceive: Date { lock.lock(); defer { lock.unlock() }; return lastRx }

    private final class Capture {
        var messages: [HPDMessage] = []
        var lastRx: Date?
    }

    public init(transport: SysExTransport) {
        self.transport = transport
    }

    // MARK: - Réception (depuis le callback CoreMIDI, tout thread)

    public func receive(bytes: [UInt8]) {
        lock.lock()
        let events = parser.feed(bytes)
        if bytes.contains(where: { $0 < 0xF8 }) { lastRx = Date() }
        lock.unlock()
        for e in events {
            switch e {
            case .sysex(let f): handle(f)
            case .channel(let m): onChannelMessage?(m)
            }
        }
    }

    private func handle(_ frame: [UInt8]) {
        let msg = Roland.parse(frame)
        switch msg {
        case .dt1(_, let a, let d): log(.rx, "DT1 \(a) · \(d.count) oct · \(Self.preview(d))")
        case .identityReply(let dev, let p): log(.rx, "Identity Reply (dev \(String(format: "%02X", dev))) : \(p.hex)")
        case .invalid(let why, let raw): log(.error, "Trame invalide : \(why) · \(Self.preview(raw))")
        case .other(let raw): log(.rx, "SysEx non géré · \(raw.count) oct · \(Self.preview(raw))")
        }
        lock.lock()
        if let c = capture {
            c.messages.append(msg)
            c.lastRx = Date()
        }
        lock.unlock()
    }

    // MARK: - Requête + capture

    /// Envoie `frame` puis rassemble les SysEx reçus.
    /// Fin : `until` satisfait, ou `quiet` secondes sans rien recevoir après une première réponse,
    /// ou `firstTimeout` sans aucune réponse, ou `maxDuration`.
    public func exchange(_ frame: [UInt8], label: String,
                         firstTimeout: TimeInterval = 2.0,
                         quiet: TimeInterval = 0.6,
                         maxDuration: TimeInterval = 15,
                         retries: Int? = nil,
                         until: (([HPDMessage]) -> Bool)? = nil) async throws -> [HPDMessage] {
        var attempt = 0
        while true {
            let msgs = try await exchangeOnce(frame, label: attempt == 0 ? label : "\(label) (nouvel essai \(attempt))",
                                              firstTimeout: firstTimeout, quiet: quiet, maxDuration: maxDuration, until: until)
            if !msgs.isEmpty || attempt >= (retries ?? self.retries) { return msgs }
            attempt += 1
        }
    }

    private func exchangeOnce(_ frame: [UInt8], label: String, firstTimeout: TimeInterval, quiet: TimeInterval,
                              maxDuration: TimeInterval, until: (([HPDMessage]) -> Bool)?) async throws -> [HPDMessage] {
        await waitSlot(for: frame)          // attendre AVANT d'ouvrir la capture
        let c = Capture()
        lock.lock()
        if capture != nil { lock.unlock(); throw HPDError.busy }
        capture = c
        lock.unlock()
        defer { lock.lock(); capture = nil; lock.unlock() }

        try await transmit(frame, label: label)

        let start = Date()
        while true {
            try? await Task.sleep(nanoseconds: 20_000_000)
            lock.lock()
            let msgs = c.messages
            let last = c.lastRx
            lock.unlock()
            let now = Date()
            if let u = until, u(msgs) { return msgs }
            if let l = last {
                if now.timeIntervalSince(l) >= quiet { return msgs }
            } else if now.timeIntervalSince(start) >= firstTimeout {
                log(.info, "Aucune réponse à : \(label)")
                return msgs
            }
            if now.timeIntervalSince(start) >= maxDuration {
                log(.error, "Durée maximale atteinte : \(label)")
                return msgs
            }
        }
    }

    /// Identity Request ; renvoie la charge utile de l'Identity Reply (41 2E 01 …) ou nil.
    public func identity() async throws -> [UInt8]? {
        func reply(_ msgs: [HPDMessage]) -> [UInt8]? {
            for m in msgs { if case .identityReply(_, let p) = m { return p } }
            return nil
        }
        let msgs = try await exchange(Roland.identityRequest(device: 0x7F), label: "Identity Request",
                                      until: { reply($0) != nil })
        return reply(msgs)
    }

    /// RQ1 ; renvoie toutes les trames DT1 reçues (adresse, données), dans l'ordre d'arrivée.
    public func request(_ address: HPDAddress, size: HPDAddress, label: String,
                        firstTimeout: TimeInterval = 1.5, quiet: TimeInterval = 0.6, retries: Int? = nil) async throws -> [(address: HPDAddress, data: [UInt8])] {
        let msgs = try await exchange(Roland.rq1(device: deviceByte, address: address, size: size),
                                      label: "RQ1 \(label) \(address) taille \(size)",
                                      firstTimeout: firstTimeout, quiet: quiet, retries: retries)
        var out: [(address: HPDAddress, data: [UInt8])] = []
        for m in msgs {
            if case .dt1(_, let a, let d) = m { out.append((address: a, data: d)) }
        }
        return out
    }

    /// RQ1 d'un bloc précis : renvoie les `size` octets s'ils sont tous reçus, sinon nil.
    public func readExact(_ address: HPDAddress, size: Int, label: String,
                          firstTimeout: TimeInterval = 1.0, retries: Int? = nil) async throws -> [UInt8]? {
        let start = address.value
        func assemble(_ msgs: [HPDMessage]) -> [UInt8]? {
            var buf = [UInt8?](repeating: nil, count: size)
            for m in msgs {
                guard case .dt1(_, let a, let d) = m else { continue }
                for (i, b) in d.enumerated() {
                    let idx = a.value - start + i
                    if idx >= 0 && idx < size { buf[idx] = b }
                }
            }
            return buf.contains(where: { $0 == nil }) ? nil : buf.map { $0! }
        }
        let msgs = try await exchange(Roland.rq1(device: deviceByte, address: address, size: size),
                                      label: "RQ1 \(label) \(address) taille \(size)",
                                      firstTimeout: firstTimeout, retries: retries,
                                      until: { assemble($0) != nil })
        return assemble(msgs)
    }

    // MARK: - Écriture

    /// DT1 vers l'appareil, paquets ≤ 128 octets espacés d'au moins `dt1Interval`.
    public func write(_ address: HPDAddress, data: [UInt8], label: String = "DT1") async throws {
        var offset = 0
        while offset < data.count {
            let n = min(128, data.count - offset)
            let chunk = Array(data[offset..<(offset + n)])
            let addr = address.adding(offset)
            let frame = Roland.dt1(device: deviceByte, address: addr, data: chunk)
            try await transmit(frame, label: "\(label) \(addr)")
            offset += n
        }
    }

    /// Message de canal brut (Bank Select / Program Change…).
    public func sendRaw(_ bytes: [UInt8], label: String) async throws {
        try await transmit(bytes, label: label)
    }

    /// Seul point d'émission : respecte le silence après réception et l'écart entre DT1.
    /// Le créneau d'un DT1 est réservé sous verrou : plusieurs écritures lancées en même temps
    /// restent espacées d'au moins `dt1Interval`.
    private func transmit(_ frame: [UInt8], label: String) async throws {
        let isDT1 = Self.isDT1(frame)
        lock.lock()
        var slot = Date()
        if isDT1 {
            slot = max(slot, lastDT1.addingTimeInterval(dt1Interval))
            lastDT1 = slot
        }
        lock.unlock()
        while true {
            lock.lock()
            let target = max(slot, lastRx.addingTimeInterval(turnaround))
            lock.unlock()
            let wait = target.timeIntervalSinceNow
            if wait <= 0 { break }
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        log(.tx, "\(label) · \(frame.hex)")
        try transport.send(frame)
        if isDT1 { lock.lock(); lastDT1 = max(lastDT1, Date()); lock.unlock() }
    }

    static func isDT1(_ frame: [UInt8]) -> Bool {
        frame.count > 6 && frame[0] == 0xF0 && frame[Roland.cmdIndex] == Roland.cmdDT1
    }

    private func waitSlot(for frame: [UInt8]) async {
        while true {
            lock.lock()
            let wait = lastRx.addingTimeInterval(turnaround).timeIntervalSinceNow
            lock.unlock()
            if wait <= 0 { break }
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    // MARK: - Utilitaires

    public func log(_ d: HPDLogEntry.Direction, _ s: String) {
        onLog?(HPDLogEntry(d, s))
    }

    public static func preview(_ bytes: [UInt8], limit: Int = 48) -> String {
        if bytes.count <= limit { return bytes.hex }
        return Array(bytes.prefix(limit)).hex + " … (+\(bytes.count - limit))"
    }
}
