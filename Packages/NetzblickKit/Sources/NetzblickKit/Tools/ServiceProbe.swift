import Foundation
import Network
import os

/// A well-known TCP service, with a plain-German name.
public struct KnownService: Hashable, Sendable, Identifiable {
    public var port: UInt16
    public var name: String
    /// Old or unencrypted remote access that should not be open on a home device.
    public var isRisky: Bool
    /// Typical for network cameras (Fing's "find hidden cameras").
    public var isCamera: Bool

    public var id: UInt16 { port }

    public init(port: UInt16, name: String, isRisky: Bool = false, isCamera: Bool = false) {
        self.port = port
        self.name = name
        self.isRisky = isRisky
        self.isCamera = isCamera
    }

    /// Short list Netzblick checks. Deliberately small: this is a look, not a full port scan.
    public static let common: [KnownService] = [
        KnownService(port: 21, name: "Dateiübertragung (FTP)", isRisky: true),
        KnownService(port: 22, name: "Fernsteuerung (SSH)"),
        KnownService(port: 23, name: "Fernsteuerung ohne Verschlüsselung (Telnet)", isRisky: true),
        KnownService(port: 80, name: "Weboberfläche"),
        KnownService(port: 443, name: "Weboberfläche (HTTPS)"),
        KnownService(port: 445, name: "Dateifreigabe (SMB)"),
        KnownService(port: 548, name: "Dateifreigabe (AFP)"),
        KnownService(port: 554, name: "Videostream (RTSP)", isCamera: true),
        KnownService(port: 631, name: "Drucken (IPP)"),
        KnownService(port: 1883, name: "Smart-Home-Nachrichten (MQTT)"),
        KnownService(port: 3389, name: "Fernzugriff auf den Bildschirm (RDP)", isRisky: true),
        KnownService(port: 5000, name: "Weboberfläche (Port 5000)"),
        KnownService(port: 5001, name: "Weboberfläche (Port 5001)"),
        KnownService(port: 5900, name: "Bildschirmfreigabe (VNC)", isRisky: true),
        KnownService(port: 8000, name: "Kamera-Steuerung (ONVIF)", isCamera: true),
        KnownService(port: 8080, name: "Weboberfläche (Port 8080)"),
        KnownService(port: 8443, name: "Weboberfläche (Port 8443)"),
        KnownService(port: 8554, name: "Videostream (RTSP)", isCamera: true),
        KnownService(port: 9100, name: "Drucken (RAW)")
    ]
}

/// Checks which of the known services a device in the home network answers on.
/// A TCP handshake only, nothing is sent; at most `KnownService.common.count` connections per device.
public struct ServiceProbe: Sendable {
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 1) {
        self.timeout = timeout
    }

    public func openServices(host: String, among services: [KnownService] = KnownService.common) async -> [KnownService] {
        await withTaskGroup(of: KnownService?.self) { group in
            for service in services {
                group.addTask { await isOpen(host: host, port: service.port) ? service : nil }
            }
            var open: [KnownService] = []
            for await result in group {
                if let result { open.append(result) }
            }
            return open.sorted { $0.port < $1.port }
        }
    }

    public func isOpen(host: String, port: UInt16) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let done = OSAllocatedUnfairLock(initialState: false)
        let timeout = self.timeout
        return await withCheckedContinuation { continuation in
            @Sendable func finish(_ open: Bool) {
                let first = done.withLock { (finished: inout Bool) -> Bool in
                    defer { finished = true }
                    return !finished
                }
                guard first else { return }
                connection.cancel()
                continuation.resume(returning: open)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                // "waiting" is how Network reports a refused connection.
                case .failed, .waiting, .cancelled: finish(false)
                default: break
                }
            }
            let queue = DispatchQueue(label: "netzblick.probe.\(port)")
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }
}
