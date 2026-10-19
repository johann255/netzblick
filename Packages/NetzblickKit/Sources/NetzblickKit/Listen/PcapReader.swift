import Foundation

/// One captured frame from a pcap stream.
public struct CapturedFrame: Hashable, Sendable {
    /// pcap link type: 1 = Ethernet, 113 = Linux cooked capture.
    public var linkType: UInt32
    public var timestamp: Date
    public var data: Data
}

/// Reads a classic pcap stream incrementally, as it arrives from the FRITZ!Box capture.
///
/// VERIFY: the FRITZ!Box writes classic libpcap (magic a1b2c3d4), not pcapng.
public struct PcapReader: Sendable {
    public enum ReadError: Error, Equatable {
        case notPcap
        case pcapNGUnsupported
    }

    private var buffer = Data()
    private var littleEndian = true
    private var nanoseconds = false
    public private(set) var linkType: UInt32?

    public init() {}

    /// Appends bytes and returns every frame that is now complete.
    public mutating func feed(_ chunk: Data) throws -> [CapturedFrame] {
        buffer.append(chunk)
        var frames: [CapturedFrame] = []
        if linkType == nil {
            guard buffer.count >= 24 else { return [] }
            try readGlobalHeader()
        }
        guard let linkType else { return [] }
        var offset = buffer.startIndex
        while buffer.endIndex - offset >= 16 {
            let seconds = read32(at: offset)
            let fraction = read32(at: offset + 4)
            let captured = Int(read32(at: offset + 8))
            guard buffer.endIndex - offset - 16 >= captured else { break }
            let start = offset + 16
            let time = Double(seconds) + Double(fraction) / (nanoseconds ? 1_000_000_000 : 1_000_000)
            frames.append(CapturedFrame(
                linkType: linkType,
                timestamp: Date(timeIntervalSince1970: time),
                data: Data(buffer[start..<start + captured])
            ))
            offset = start + captured
        }
        buffer = Data(buffer[offset...])
        return frames
    }

    private mutating func readGlobalHeader() throws {
        let magic = buffer.prefix(4).map { $0 }
        switch magic {
        case [0xD4, 0xC3, 0xB2, 0xA1]: littleEndian = true; nanoseconds = false
        case [0x4D, 0x3C, 0xB2, 0xA1]: littleEndian = true; nanoseconds = true
        case [0xA1, 0xB2, 0xC3, 0xD4]: littleEndian = false; nanoseconds = false
        case [0xA1, 0xB2, 0x3C, 0x4D]: littleEndian = false; nanoseconds = true
        case [0x0A, 0x0D, 0x0D, 0x0A]: throw ReadError.pcapNGUnsupported
        default: throw ReadError.notPcap
        }
        linkType = read32(at: buffer.startIndex + 20)
        buffer = Data(buffer.dropFirst(24))
    }

    private func read32(at index: Data.Index) -> UInt32 {
        let b = buffer[index..<index + 4].map(UInt32.init)
        return littleEndian
            ? b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24
            : b[3] | b[2] << 8 | b[1] << 16 | b[0] << 24
    }
}
