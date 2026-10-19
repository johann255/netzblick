import Foundation

/// User names of a FRITZ!Box, readable without login via `LANConfigSecurity:X_AVM-DE_GetUserList`.
///
/// A box where nobody set a user name still has one: FRITZ!OS creates it automatically (e.g. "fritz2690")
/// and the web login only asks for the password. TR-064 always needs the name, so the app looks it up.
public struct BoxUsers: Hashable, Sendable {
    public var names: [String]
    /// The user that last logged in to the box, marked `last_user="1"`.
    public var lastUsed: String?

    /// The name to use when the person left the field empty.
    public var suggested: String? { lastUsed ?? names.first }

    /// Parses the list, e.g. `<List><Username last_user="1">fritz2690</Username></List>`.
    public static func parse(_ xml: String) -> BoxUsers {
        let delegate = UserListParser()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        parser.parse()
        return BoxUsers(names: delegate.names, lastUsed: delegate.lastUsed)
    }
}

extension TR064Client {
    /// Reads the box's user names. Needs no login.
    public func loadUsers(_ catalog: ServiceCatalog) async throws -> BoxUsers {
        let out = try await call(catalog, "LANConfigSecurity", action: "X_AVM-DE_GetUserList")
        guard let list = out["NewX_AVM-DE_UserList"] else { throw TR064Error.malformedResponse("X_AVM-DE_UserList") }
        return BoxUsers.parse(list)
    }
}

private final class UserListParser: NSObject, XMLParserDelegate {
    var names: [String] = []
    var lastUsed: String?
    private var current: String?
    private var isLast = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "Username" else { return }
        current = ""
        isLast = attributeDict["last_user"] == "1"
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        current? += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "Username", let name = current?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        current = nil
        guard !name.isEmpty else { return }
        names.append(name)
        if isLast { lastUsed = name }
    }
}
