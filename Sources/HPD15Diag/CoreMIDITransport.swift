import Foundation
import CoreMIDI
import HPD15Core

struct MIDIPortInfo {
    let ref: MIDIEndpointRef
    let name: String
}

/// Transport CoreMIDI : une entrée (source) et une sortie (destination).
/// Le HPD-15 est relié par ses MIDI IN/OUT à une interface Roland UM-ONE (USB côté Mac).
final class CoreMIDITransport: SysExTransport {
    var onReceive: (([UInt8]) -> Void)?

    private var client = MIDIClientRef()
    private var inPort = MIDIPortRef()
    private var outPort = MIDIPortRef()
    private var source: MIDIEndpointRef = 0
    private var destination: MIDIEndpointRef = 0

    init() {
        MIDIClientCreateWithBlock("HPD15Diag" as CFString, &client) { _ in }
        MIDIInputPortCreateWithBlock(client, "Entrée" as CFString, &inPort) { [weak self] list, _ in
            self?.handle(list)
        }
        MIDIOutputPortCreate(client, "Sortie" as CFString, &outPort)
    }

    deinit {
        disconnect()
        MIDIPortDispose(inPort)
        MIDIPortDispose(outPort)
        MIDIClientDispose(client)
    }

    static func displayName(_ obj: MIDIObjectRef) -> String {
        var cf: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &cf)
        if let u = cf { return u.takeRetainedValue() as String }
        return "Inconnu"
    }

    func sources() -> [MIDIPortInfo] {
        (0..<MIDIGetNumberOfSources()).map {
            let r = MIDIGetSource($0)
            return MIDIPortInfo(ref: r, name: Self.displayName(r))
        }
    }

    func destinations() -> [MIDIPortInfo] {
        (0..<MIDIGetNumberOfDestinations()).map {
            let r = MIDIGetDestination($0)
            return MIDIPortInfo(ref: r, name: Self.displayName(r))
        }
    }

    func connect(source newSource: MIDIEndpointRef, destination newDestination: MIDIEndpointRef) {
        disconnect()
        if newSource != 0 {
            MIDIPortConnectSource(inPort, newSource, nil)
            source = newSource
        }
        destination = newDestination
    }

    func disconnect() {
        if source != 0 { MIDIPortDisconnectSource(inPort, source) }
        source = 0
        destination = 0
    }

    private func handle(_ list: UnsafePointer<MIDIPacketList>) {
        // Lecture par pointeur brut : le tuple `data` de MIDIPacket ne couvre que 256 octets.
        let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.data) ?? 10
        for packet in list.unsafeSequence() {
            let length = Int(packet.pointee.length)
            guard length > 0 else { continue }
            let base = UnsafeRawPointer(packet).advanced(by: dataOffset)
            let bytes = [UInt8](UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: length))
            onReceive?(bytes)
        }
    }

    func send(_ bytes: [UInt8]) throws {
        guard destination != 0 else { throw HPDError.notConnected }
        var buffer = [UInt8](repeating: 0, count: bytes.count + 256)
        let status: OSStatus = buffer.withUnsafeMutableBytes { raw -> OSStatus in
            let list = raw.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
            let first = MIDIPacketListInit(list)
            guard MIDIPacketListAdd(list, raw.count, first, 0, bytes.count, bytes) != nil else {
                return OSStatus(-50)
            }
            return MIDISend(outPort, destination, list)
        }
        if status != noErr {
            throw HPDError.invalid("MIDISend a échoué (OSStatus \(status)).")
        }
    }
}
