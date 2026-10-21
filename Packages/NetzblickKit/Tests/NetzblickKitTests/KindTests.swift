import XCTest
@testable import NetzblickKit

final class DeviceKindTests: XCTestCase {
    let classifier = DeviceClassifier()

    private func kind(_ name: String, vendor: String? = nil, bonjour: [String] = []) -> DeviceKind {
        classifier.kind(for: Device(id: name, name: name, vendor: vendor, bonjourServices: bonjour))
    }

    func testNames() {
        let expected: [String: DeviceKind] = [
            "Johanns-MBP": .laptop, "MBP-von-Anna": .laptop, "MB-Air": .laptop, "MBA13": .laptop,
            "Johanns-MacBook-Pro": .laptop, "ThinkPad-X1": .laptop,
            "Mac-mini": .desktop, "iMac-Buero": .desktop, "Gaming-PC": .desktop,
            "Annas-iPhone": .iPhone, "iPad-Wohnzimmer": .tablet, "Galaxy-Tab-S8": .tablet,
            "Galaxy-S24": .smartphone, "android-1a2b3c": .smartphone, "SM-G991B": .smartphone, "Pixel-8": .smartphone,
            "Apple-Watch": .watch, "Kindle": .eReader,
            "Sonos-Kueche": .speaker, "Echo-Dot": .speaker, "HomePod-Bad": .homePod,
            "Samsung-TV": .tv, "LGwebOSTV": .tv, "Apple-TV": .appleTV, "Fire-TV-Stick": .streamingBox, "Chromecast": .streamingBox,
            "PS5": .console, "Nintendo-Switch": .console, "XboxOne": .console,
            "Meross-Smart-Plug": .smartPlug, "shellyplug-s-1A2B": .smartPlug, "FRITZ!DECT 200": .smartPlug,
            "Eve-Energy": .sensor, "Hue-Bridge": .hub, "Nanoleaf": .light, "WLED-Kueche": .light,
            "tado-Thermostat": .thermostat, "Roborock-S7": .vacuum, "Automower": .mower,
            "Miele-Waschmaschine": .appliance, "Wallbox": .evCharger, "OpenDTU": .solar,
            "Kamera Garten": .camera, "Tapo-C200": .camera, "Türklingel": .doorbell, "Nuki-Bridge": .lock,
            "DS920": .nas, "NAS-Keller": .nas, "raspberrypi": .server, "homeassistant": .server,
            "HP-OfficeJet": .printer, "BRN-MFC-L2710": .printer,
            "FRITZ!Repeater 3000": .repeater, "FRITZ!Box 7590": .router, "devolo-Magic": .powerline
        ]
        for (name, kind) in expected {
            XCTAssertEqual(self.kind(name), kind, name)
        }
    }

    func testFritzDefaultNameSaysNothing() {
        XCTAssertEqual(kind("PC-192-168-178-40"), .unknown)
        XCTAssertEqual(kind("PC-192-168-178-40", vendor: "Sonos"), .speaker)
    }

    func testWordsMustBeWhole() {
        XCTAssertNotEqual(kind("Combi"), .laptop, "\"mb\" inside a word is not a MacBook")
        XCTAssertNotEqual(kind("Steckdose-Bad"), .laptop)
    }

    func testServicesAndVendors() {
        XCTAssertEqual(kind("Wohnzimmer", bonjour: ["_sonos._tcp"]), .speaker)
        XCTAssertEqual(kind("unbekannt", vendor: "Meross"), .smartPlug)
        XCTAssertEqual(kind("unbekannt", vendor: "Espressif"), .smartHomeDevice)
    }

    func testKindDrivesCategoryAndIcon() {
        XCTAssertEqual(DeviceKind.laptop.category, .computer)
        XCTAssertEqual(DeviceKind.speaker.category, .entertainment)
        XCTAssertEqual(DeviceKind.smartPlug.category, .smartHome)
        let device = Device(id: "x", name: "x", category: .computer, kind: .laptop)
        XCTAssertEqual(device.symbolName, "laptopcomputer")
        XCTAssertEqual(Device(id: "y", name: "y", category: .printer).kind, .printer, "generic kind from category")
    }

    func testEveryKindHasTextAndIcon() {
        for kind in DeviceKind.allCases {
            XCTAssertFalse(kind.title.isEmpty)
            XCTAssertFalse(kind.symbolName.isEmpty)
        }
    }

    func testDemoUsesSpecificKinds() {
        let devices = DemoHousehold.snapshot().devices
        XCTAssertEqual(devices.first { $0.name == "MacBook" }?.kind, .laptop)
        XCTAssertEqual(devices.first { $0.name == "Sonos Küche" }?.kind, .speaker)
        XCTAssertEqual(devices.first { $0.name == "Smarte Steckdose 1" }?.kind, .smartPlug)
    }
}
