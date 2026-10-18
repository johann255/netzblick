import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Errors from talking to the FRITZ!Box, with plain-German descriptions for the UI.
public enum TR064Error: Error, Equatable, Sendable, LocalizedError {
    case unreachable
    case unauthorized
    case accessDisabled
    case serviceMissing(String)
    case httpStatus(Int)
    case soapFault(code: Int?, description: String)
    case malformedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .unreachable:
            return "Die FRITZ!Box ist nicht erreichbar. Ist dieses iPhone im Heim-WLAN?"
        case .unauthorized:
            return "Benutzername oder Kennwort stimmen nicht."
        case .accessDisabled:
            return "In der FRITZ!Box ist der Zugriff für Anwendungen ausgeschaltet."
        case let .serviceMissing(name):
            return "Diese FRITZ!Box bietet den Dienst \(name) nicht an."
        case let .httpStatus(code):
            return "Die FRITZ!Box hat unerwartet geantwortet (HTTP \(code))."
        case let .soapFault(code, description):
            if let code { return "Die FRITZ!Box meldet einen Fehler (\(code)): \(description)" }
            return "Die FRITZ!Box meldet einen Fehler: \(description)"
        case let .malformedResponse(what):
            return "Die Antwort der FRITZ!Box war unvollständig (\(what))."
        }
    }
}

/// Builds TR-064 SOAP request bodies.
public enum SOAPEnvelope {
    public static func body(serviceType: String, action: String, arguments: [(String, String)] = []) -> Data {
        var args = ""
        for (name, value) in arguments {
            args += "<\(name)>\(escape(value))</\(name)>"
        }
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
        <s:Body><u:\(action) xmlns:u="\(serviceType)">\(args)</u:\(action)></s:Body></s:Envelope>
        """
        return Data(xml.utf8)
    }

    public static func soapActionHeader(serviceType: String, action: String) -> String {
        "\"\(serviceType)#\(action)\""
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

/// Parses a SOAP response into the output arguments of `<u:ActionResponse>`, or a fault.
public enum SOAPResponseParser {
    public static func parse(_ data: Data, action: String) throws -> [String: String] {
        let delegate = SOAPParserDelegate(responseName: action + "Response")
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else {
            throw TR064Error.malformedResponse("XML")
        }
        if delegate.isFault {
            let code = delegate.faultFields["errorCode"].flatMap { Int($0) }
            let description = delegate.faultFields["errorDescription"] ?? delegate.faultFields["faultstring"] ?? "unbekannt"
            throw TR064Error.soapFault(code: code, description: description)
        }
        guard delegate.foundResponse else {
            throw TR064Error.malformedResponse(action)
        }
        return delegate.values
    }
}

private final class SOAPParserDelegate: NSObject, XMLParserDelegate {
    let responseName: String
    var values: [String: String] = [:]
    var faultFields: [String: String] = [:]
    var foundResponse = false
    var isFault = false

    private var depthInResponse = 0
    private var inFault = false
    private var currentText = ""

    init(responseName: String) {
        self.responseName = responseName
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        if elementName == responseName {
            foundResponse = true
            depthInResponse = 1
            return
        }
        if elementName == "Fault" {
            inFault = true
            isFault = true
            return
        }
        if depthInResponse > 0 { depthInResponse += 1 }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if depthInResponse > 0 {
            if elementName == responseName {
                depthInResponse = 0
            } else {
                // Direct children of the response element are the output arguments.
                if depthInResponse == 2 { values[elementName] = text }
                depthInResponse -= 1
            }
        } else if inFault {
            if elementName == "Fault" { inFault = false } else if !text.isEmpty { faultFields[elementName] = text }
        }
        currentText = ""
    }
}

/// Parses the XML lists the FRITZ!Box hands out by path (host list, WLAN device list):
/// `<List><Item><Field>value</Field>…</Item>…</List>` into one dictionary per item.
public enum ItemListParser {
    public static func parse(_ data: Data) throws -> [[String: String]] {
        let delegate = ItemListDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw TR064Error.malformedResponse("Liste") }
        return delegate.items
    }
}

private final class ItemListDelegate: NSObject, XMLParserDelegate {
    var items: [[String: String]] = []
    private var current: [String: String]?
    private var depthInItem = 0
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "Item", current == nil {
            current = [:]
            depthInItem = 1
        } else if current != nil {
            depthInItem += 1
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard current != nil else { return }
        if elementName == "Item", depthInItem == 1 {
            if let current { items.append(current) }
            current = nil
            depthInItem = 0
        } else {
            if depthInItem == 2 {
                current?[elementName] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            depthInItem -= 1
        }
        text = ""
    }
}
