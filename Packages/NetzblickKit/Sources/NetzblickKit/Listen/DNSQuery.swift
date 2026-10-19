import Foundation

/// A DNS question a device sent, taken from a captured frame. Answers and contents are never read.
public struct DNSQuery: Hashable, Sendable {
    /// Upper-cased MAC of the asking device, as `Device.id` uses it.
    public var sourceMAC: String?
    public var sourceIP: String
    /// Lower-cased name without trailing dot, e.g. "graph.facebook.com".
    public var name: String
    /// 1 = A, 28 = AAAA, 65 = HTTPS, 12 = PTR, ...
    public var type: UInt16
    public var timestamp: Date

    public init(sourceMAC: String?, sourceIP: String, name: String, type: UInt16, timestamp: Date) {
        self.sourceMAC = sourceMAC
        self.sourceIP = sourceIP
        self.name = name
        self.type = type
        self.timestamp = timestamp
    }

    /// Extracts the question from an outgoing DNS query (UDP to port 53). Returns nil for anything else.
    public static func parse(_ frame: CapturedFrame) -> DNSQuery? {
        let bytes = [UInt8](frame.data)
        var offset: Int
        var etherType: Int
        var mac: String?

        switch frame.linkType {
        case 1: // Ethernet
            guard bytes.count >= 14 else { return nil }
            mac = formatMAC(bytes[6..<12])
            etherType = Int(bytes[12]) << 8 | Int(bytes[13])
            offset = 14
        case 113: // Linux cooked capture (SLL)
            guard bytes.count >= 16 else { return nil }
            let addressLength = Int(bytes[4]) << 8 | Int(bytes[5])
            if addressLength == 6 { mac = formatMAC(bytes[6..<12]) }
            etherType = Int(bytes[14]) << 8 | Int(bytes[15])
            offset = 16
        case 276: // Linux cooked capture v2 (SLL2)
            guard bytes.count >= 20 else { return nil }
            etherType = Int(bytes[0]) << 8 | Int(bytes[1])
            if bytes[11] == 6 { mac = formatMAC(bytes[12..<18]) }
            offset = 20
        default:
            return nil
        }
        // VLAN tags
        while etherType == 0x8100 || etherType == 0x88A8 {
            guard bytes.count >= offset + 4 else { return nil }
            etherType = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            offset += 4
        }

        let sourceIP: String
        switch etherType {
        case 0x0800: // IPv4
            guard bytes.count >= offset + 20, bytes[offset] >> 4 == 4, bytes[offset + 9] == 17 else { return nil }
            let headerLength = Int(bytes[offset] & 0x0F) * 4
            sourceIP = bytes[offset + 12..<offset + 16].map(String.init).joined(separator: ".")
            offset += headerLength
        case 0x86DD: // IPv6, no extension headers
            guard bytes.count >= offset + 40, bytes[offset + 6] == 17 else { return nil }
            sourceIP = formatIPv6(bytes[offset + 8..<offset + 24])
            offset += 40
        default:
            return nil
        }

        // UDP
        guard bytes.count >= offset + 8 else { return nil }
        let destinationPort = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        guard destinationPort == 53 else { return nil }
        offset += 8

        // DNS header: must be a standard query with at least one question.
        guard bytes.count >= offset + 12 else { return nil }
        let isResponse = bytes[offset + 2] & 0x80 != 0
        let opcode = (bytes[offset + 2] >> 3) & 0x0F
        let questions = Int(bytes[offset + 4]) << 8 | Int(bytes[offset + 5])
        guard !isResponse, opcode == 0, questions >= 1 else { return nil }
        offset += 12

        var labels: [String] = []
        while true {
            guard offset < bytes.count else { return nil }
            let length = Int(bytes[offset])
            if length == 0 { offset += 1; break }
            // Questions are not compressed; a pointer here means a malformed packet.
            guard length < 64, offset + 1 + length <= bytes.count else { return nil }
            guard let label = String(bytes: bytes[offset + 1..<offset + 1 + length], encoding: .utf8) else { return nil }
            labels.append(label.lowercased())
            offset += 1 + length
        }
        guard !labels.isEmpty, bytes.count >= offset + 2 else { return nil }
        let type = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])

        return DNSQuery(sourceMAC: mac, sourceIP: sourceIP, name: labels.joined(separator: "."), type: type, timestamp: frame.timestamp)
    }

    private static func formatMAC(_ bytes: ArraySlice<UInt8>) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private static func formatIPv6(_ bytes: ArraySlice<UInt8>) -> String {
        let a = Array(bytes)
        return stride(from: 0, to: 16, by: 2)
            .map { String(Int(a[$0]) << 8 | Int(a[$0 + 1]), radix: 16) }
            .joined(separator: ":")
    }
}
