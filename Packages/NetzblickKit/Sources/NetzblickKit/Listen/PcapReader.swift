import Foundation

/// One captured frame from a capture stream.
public struct CapturedFrame: Hashable, Sendable {
    /// pcap link type: 1 = Ethernet, 113 = Linux cooked capture.
    public var linkType: UInt32
    public var timestamp: Date
    public var data: Data
}

/// Reads a capture stream incrementally, as it arrives from the FRITZ!Box.
///
/// Understands classic pcap (µs and ns), the "modified" pcap variant with longer record headers,
/// and pcapng (section, interface, enhanced and simple packet blocks).
public struct PcapReader: Sendable {
    public enum ReadError: Error, Equatable {
        /// First bytes of the stream, in hex, for the error message.
        case unknownFormat(String)
    }

    private enum Format {
        case pcap(nanoseconds: Bool, recordHeader: Int)
        case pcapng
    }

    private var buffer = Data()
    private var littleEndian = true
    private var format: Format?
    /// Link type of the classic stream, or per interface for pcapng.
    private var linkTypes: [UInt32] = []

    public init() {}

    public var linkType: UInt32? { linkTypes.first }

    /// Appends bytes and returns every frame that is now complete.
    public mutating func feed(_ chunk: Data) throws -> [CapturedFrame] {
        buffer.append(chunk)
        if format == nil {
            guard buffer.count >= 24 else { return [] }
            try detectFormat()
        }
        var frames: [CapturedFrame] = []
        var offset = 0
        let bytes = [UInt8](buffer)
        switch format {
        case let .pcap(nanoseconds, recordHeader):
            if offset == 0, linkTypes.isEmpty { return [] }
            while bytes.count - offset >= recordHeader {
                let seconds = read32(bytes, offset)
                let fraction = read32(bytes, offset + 4)
                let captured = Int(read32(bytes, offset + 8))
                guard bytes.count - offset - recordHeader >= captured else { break }
                let start = offset + recordHeader
                let time = Double(seconds) + Double(fraction) / (nanoseconds ? 1_000_000_000 : 1_000_000)
                frames.append(CapturedFrame(linkType: linkTypes[0], timestamp: Date(timeIntervalSince1970: time),
                                            data: Data(bytes[start..<start + captured])))
                offset = start + captured
            }
        case .pcapng:
            while bytes.count - offset >= 12 {
                // A new section may switch byte order.
                if read32raw(bytes, offset) == 0x0A0D0D0A {
                    let magic = Array(bytes[offset + 8..<offset + 12])
                    littleEndian = magic == [0x4D, 0x3C, 0x2B, 0x1A]
                    linkTypes = []
                }
                let type = read32(bytes, offset)
                let length = Int(read32(bytes, offset + 4))
                guard length >= 12, length % 4 == 0 else { throw ReadError.unknownFormat(Self.hex(bytes, offset)) }
                guard bytes.count - offset >= length else { break }
                switch type {
                case 1 where length >= 20: // Interface description
                    linkTypes.append(UInt32(read16(bytes, offset + 8)))
                case 6 where length >= 32: // Enhanced packet
                    let interface = Int(read32(bytes, offset + 8))
                    let high = UInt64(read32(bytes, offset + 12))
                    let low = UInt64(read32(bytes, offset + 16))
                    let captured = Int(read32(bytes, offset + 20))
                    let start = offset + 28
                    if interface < linkTypes.count, start + captured <= offset + length {
                        frames.append(CapturedFrame(
                            linkType: linkTypes[interface],
                            timestamp: Date(timeIntervalSince1970: Double(high << 32 | low) / 1_000_000),
                            data: Data(bytes[start..<start + captured])
                        ))
                    }
                case 3 where length >= 16: // Simple packet
                    let original = Int(read32(bytes, offset + 8))
                    let captured = min(original, length - 16)
                    if let link = linkTypes.first {
                        frames.append(CapturedFrame(linkType: link, timestamp: Date(),
                                                    data: Data(bytes[offset + 12..<offset + 12 + captured])))
                    }
                default:
                    break
                }
                offset += length
            }
        case nil:
            break
        }
        buffer = Data(bytes[offset...])
        return frames
    }

    private mutating func detectFormat() throws {
        let bytes = [UInt8](buffer.prefix(24))
        switch Array(bytes[0..<4]) {
        case [0xD4, 0xC3, 0xB2, 0xA1]: setPcap(little: true, nano: false, header: 16)
        case [0x4D, 0x3C, 0xB2, 0xA1]: setPcap(little: true, nano: true, header: 16)
        case [0xA1, 0xB2, 0xC3, 0xD4]: setPcap(little: false, nano: false, header: 16)
        case [0xA1, 0xB2, 0x3C, 0x4D]: setPcap(little: false, nano: true, header: 16)
        case [0x34, 0xCD, 0xB2, 0xA1]: setPcap(little: true, nano: false, header: 24)
        case [0xA1, 0xB2, 0xCD, 0x34]: setPcap(little: false, nano: false, header: 24)
        case [0x0A, 0x0D, 0x0D, 0x0A]:
            format = .pcapng
            return
        default:
            throw ReadError.unknownFormat(Self.hex(bytes, 0))
        }
        linkTypes = [read32(bytes, 20)]
        buffer = Data(buffer.dropFirst(24))
    }

    private mutating func setPcap(little: Bool, nano: Bool, header: Int) {
        littleEndian = little
        format = .pcap(nanoseconds: nano, recordHeader: header)
    }

    private func read32raw(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
    }

    private func read32(_ b: [UInt8], _ i: Int) -> UInt32 {
        littleEndian
            ? UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
            : read32raw(b, i)
    }

    private func read16(_ b: [UInt8], _ i: Int) -> UInt16 {
        littleEndian ? UInt16(b[i]) | UInt16(b[i + 1]) << 8 : UInt16(b[i]) << 8 | UInt16(b[i + 1])
    }

    static func hex(_ b: [UInt8], _ from: Int) -> String {
        b[from..<min(from + 16, b.count)].map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
