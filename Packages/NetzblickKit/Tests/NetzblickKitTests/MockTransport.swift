import Foundation
@testable import NetzblickKit

/// Answers requests from a table keyed by "<path>" (GET) or "<path>#<Action>" (SOAP).
final class MockTransport: HTTPTransport, @unchecked Sendable {
    var routes: [String: HTTPResponse] = [:]
    private(set) var requests: [HTTPRequest] = []
    private let lock = NSLock()

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.lock()
        requests.append(request)
        lock.unlock()
        let key: String
        if let soapAction = request.headers["SOAPACTION"] {
            let action = soapAction.trimmingCharacters(in: CharacterSet(charactersIn: "\"")).split(separator: "#").last.map(String.init) ?? ""
            key = "\(request.url.path)#\(action)"
        } else {
            key = request.url.path
        }
        return routes[key] ?? HTTPResponse(statusCode: 500, body: Data(Self.fault(code: 401, text: "Invalid Action").utf8))
    }

    func soap(_ path: String, _ action: String, _ values: [String: String]) {
        let args = values.map { "<\($0.key)>\($0.value)</\($0.key)>" }.joined()
        let xml = """
        <?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>\
        <u:\(action)Response xmlns:u="urn:dslforum-org:service:X:1">\(args)</u:\(action)Response></s:Body></s:Envelope>
        """
        routes["\(path)#\(action)"] = HTTPResponse(statusCode: 200, body: Data(xml.utf8))
    }

    func file(_ path: String, fixture: String) {
        routes[path] = HTTPResponse(statusCode: 200, body: Fixture.data(fixture))
    }

    static func fault(code: Int, text: String) -> String {
        """
        <?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>\
        <faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail>\
        <UPnPError xmlns="urn:dslforum-org:control-1-0"><errorCode>\(code)</errorCode>\
        <errorDescription>\(text)</errorDescription></UPnPError></detail></s:Fault></s:Body></s:Envelope>
        """
    }

    /// A box with all services from the tr64desc fixture answering sensibly.
    static func fullBox() -> MockTransport {
        let t = MockTransport()
        t.file("/tr64desc.xml", fixture: "tr64desc.xml")
        t.soap("/upnp/control/deviceinfo", "GetInfo", ["NewModelName": "FRITZ!Box 7590 AX", "NewSoftwareVersion": "8.03"])
        t.soap("/upnp/control/userif", "GetInfo", ["NewUpgradeAvailable": "1"])
        t.soap("/upnp/control/wancommonifconfig1", "GetCommonLinkProperties", [
            "NewPhysicalLinkStatus": "Up",
            "NewLayer1DownstreamMaxBitRate": "116000000",
            "NewLayer1UpstreamMaxBitRate": "42000000"
        ])
        t.soap("/upnp/control/wancommonifconfig1", "GetAddonInfos", ["NewByteReceiveRate": "1250000", "NewByteSendRate": "125000"])
        t.soap("/upnp/control/wlanconfig1", "GetInfo", ["NewEnable": "1", "NewChannel": "6", "NewSSID": "Zuhause"])
        t.soap("/upnp/control/wlanconfig2", "GetInfo", ["NewEnable": "1", "NewChannel": "36", "NewSSID": "Zuhause"])
        t.soap("/upnp/control/wlanconfig1", "X_AVM-DE_GetWLANDeviceListPath", ["NewX_AVM-DE_WLANDeviceListPath": "/wlandevicelist.lua?sid=1"])
        t.soap("/upnp/control/wlanconfig2", "X_AVM-DE_GetWLANDeviceListPath", ["NewX_AVM-DE_WLANDeviceListPath": "/wlandevicelist2.lua?sid=1"])
        t.file("/wlandevicelist.lua", fixture: "wlan1-devices.xml")
        t.file("/wlandevicelist2.lua", fixture: "wlan2-devices.xml")
        t.soap("/upnp/control/hosts", "X_AVM-DE_GetHostListPath", ["NewX_AVM-DE_HostListPath": "/devicehostlist.lua?sid=1"])
        t.file("/devicehostlist.lua", fixture: "hostlist.xml")
        return t
    }
}

enum Fixture {
    static func data(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url) else {
            fatalError("Missing fixture \(name)")
        }
        return data
    }
}
