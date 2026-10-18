import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// One TR-064 service from `tr64desc.xml`.
public struct TR064Service: Hashable, Sendable {
    /// e.g. "urn:dslforum-org:service:Hosts:1"
    public var serviceType: String
    /// e.g. "/upnp/control/hosts"
    public var controlURL: String

    public init(serviceType: String, controlURL: String) {
        self.serviceType = serviceType
        self.controlURL = controlURL
    }

    /// Short name without URN prefix and version, e.g. "Hosts" or "WLANConfiguration".
    public var shortName: String {
        let parts = serviceType.split(separator: ":")
        return parts.count >= 2 ? String(parts[parts.count - 2]) : serviceType
    }
}

/// All services the box offers, plus its model name from the description.
public struct ServiceCatalog: Hashable, Sendable {
    public var modelName: String?
    public var services: [TR064Service]

    public init(modelName: String?, services: [TR064Service]) {
        self.modelName = modelName
        self.services = services
    }

    /// Finds a service by short name and instance, e.g. `service("WLANConfiguration", instance: 2)`.
    public func service(_ shortName: String, instance: Int = 1) -> TR064Service? {
        let wanted = "urn:dslforum-org:service:\(shortName):\(instance)"
        return services.first { $0.serviceType == wanted }
    }

    /// All instances of a service, sorted by instance number (WLANConfiguration:1, :2, :3 …).
    public func instances(of shortName: String) -> [(instance: Int, service: TR064Service)] {
        services.compactMap { service -> (Int, TR064Service)? in
            guard service.shortName == shortName,
                  let last = service.serviceType.split(separator: ":").last,
                  let n = Int(last) else { return nil }
            return (n, service)
        }
        .sorted { $0.0 < $1.0 }
        .map { (instance: $0.0, service: $0.1) }
    }

    public static func parse(_ data: Data) throws -> ServiceCatalog {
        let delegate = DescriptionDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw TR064Error.malformedResponse("tr64desc.xml") }
        return ServiceCatalog(modelName: delegate.modelName, services: delegate.services)
    }
}

private final class DescriptionDelegate: NSObject, XMLParserDelegate {
    var modelName: String?
    var services: [TR064Service] = []
    private var inService = false
    private var serviceType = ""
    private var controlURL = ""
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "service" {
            inService = true
            serviceType = ""
            controlURL = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "serviceType" where inService: serviceType = value
        case "controlURL" where inService: controlURL = value
        case "service":
            if !serviceType.isEmpty, !controlURL.isEmpty {
                services.append(TR064Service(serviceType: serviceType, controlURL: controlURL))
            }
            inService = false
        case "modelName" where modelName == nil && !value.isEmpty:
            // The first modelName is the root device (the box itself).
            modelName = value
        default: break
        }
        text = ""
    }
}
