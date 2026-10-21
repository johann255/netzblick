import Foundation

/// Builds and reads ICMP echo packets (RFC 792). Pure functions, so they are tested without a network.
public enum ICMPEcho {
    static let echoRequest: UInt8 = 8
    static let echoReply: UInt8 = 0

    /// An echo request with a 16-byte payload; the checksum is filled in.
    public static func request(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var packet: [UInt8] = [echoRequest, 0, 0, 0,
                               UInt8(identifier >> 8), UInt8(identifier & 0xFF),
                               UInt8(sequence >> 8), UInt8(sequence & 0xFF)]
        packet += Array("netzblick-ping!!".utf8)
        let sum = checksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xFF)
        return packet
    }

    /// Internet checksum: one's complement of the one's-complement sum of 16-bit words.
    public static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count {
            sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1])
            i += 2
        }
        if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return ~UInt16(sum)
    }

    /// Sequence number of an echo reply, or nil for anything else.
    /// Darwin hands datagram ICMP sockets the packet with its IPv4 header, so that is skipped if present.
    public static func replySequence(_ data: [UInt8]) -> UInt16? {
        var icmp = data[...]
        if let first = data.first, first >> 4 == 4 {
            let headerLength = Int(first & 0x0F) * 4
            guard data.count >= headerLength + 8 else { return nil }
            icmp = data[headerLength...]
        }
        guard icmp.count >= 8, icmp[icmp.startIndex] == echoReply else { return nil }
        let s = icmp.startIndex
        return UInt16(icmp[s + 6]) << 8 | UInt16(icmp[s + 7])
    }
}
