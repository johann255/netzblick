import SwiftUI
import NetzblickKit

/// All devices of the home network, grouped by category, with search and status filters.
/// Guests are listed at the end and are never analysed.
struct DevicesView: View {
    @Environment(AppModel.self) private var model

    @State private var query = ""
    @State private var filter: Filter = .all

    private enum Filter: CaseIterable, Hashable {
        case all
        case online
        case new

        var title: String {
            switch self {
            case .all: return "Alle"
            case .online: return "Online"
            case .new: return "Neu"
            }
        }
    }

    var body: some View {
        NBScreen {
            NBBlueHeader(title: "Geräte", subtitle: headerSubtitle)
        } content: {
            if model.snapshot != nil {
                searchCard
                groupsContent
            } else {
                loadingView
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: String.self) { deviceID in
            DeviceDetailView(deviceID: deviceID)
        }
        .refreshable { await model.refresh() }
    }

    // MARK: - Counts

    /// Devices of the home network. Guests are listed separately and not counted.
    private var homeDevices: [Device] {
        model.snapshot?.devices.filter { !$0.isGuest } ?? []
    }

    private var onlineCount: Int {
        homeDevices.filter(\.isActive).count
    }

    private var asleepCount: Int {
        homeDevices.count - onlineCount
    }

    private var newCount: Int {
        homeDevices.filter { isNew($0) }.count
    }

    private var headerSubtitle: String? {
        guard model.snapshot != nil else { return nil }
        return "\(onlineCount) online · \(asleepCount) schlafen gerade · \(newCount) neu"
    }

    private func deviceCount(for option: Filter) -> Int {
        switch option {
        case .all: return homeDevices.count
        case .online: return onlineCount
        case .new: return newCount
        }
    }

    // MARK: - Filtering

    private func isNew(_ device: Device) -> Bool {
        model.newDeviceIDs.contains(device.id)
    }

    private func isSlow(_ device: Device) -> Bool {
        model.findings.contains { $0.kind == .slowBand && $0.deviceIDs.contains(device.id) }
    }

    private func matchesQuery(_ device: Device) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        return device.name.localizedCaseInsensitiveContains(term)
            || (device.vendor?.localizedCaseInsensitiveContains(term) ?? false)
    }

    private func matchesStatus(_ device: Device) -> Bool {
        switch filter {
        case .all: return true
        case .online: return device.isActive
        case .new: return isNew(device)
        }
    }

    private var visibleGroups: [(category: DeviceCategory, devices: [Device])] {
        (model.snapshot?.groupedDevices ?? []).compactMap { group -> (category: DeviceCategory, devices: [Device])? in
            let devices = group.devices.filter { matchesQuery($0) && matchesStatus($0) }
            guard !devices.isEmpty else { return nil }
            return (category: group.category, devices: devices)
        }
    }

    /// Guests follow the search text only; the status filter counts home devices.
    private var visibleGuests: [Device] {
        model.snapshot?.guestDevices.filter { matchesQuery($0) } ?? []
    }

    // MARK: - Search card

    private var searchCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Gerät suchen")
                    .font(.nbSans(13, weight: .semibold))
                    .foregroundStyle(Color.nbInk)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.nbMuted)
                        .accessibilityHidden(true)

                    TextField("z. B. Fernseher, Küche", text: $query)
                        .font(.nbSans(16))
                        .foregroundStyle(Color.nbInk)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .accessibilityLabel("Gerät suchen")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.nbPaper)
                )

                HStack(spacing: 8) {
                    ForEach(Filter.allCases, id: \.self) { option in
                        filterButton(option)
                    }
                }
            }
            .padding(16)
        }
    }

    private func filterButton(_ option: Filter) -> some View {
        let selected = filter == option
        return Button {
            filter = option
        } label: {
            Text("\(option.title) · \(deviceCount(for: option))")
                .font(.nbSans(13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(selected ? Color.white : Color.nbInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(selected ? Color.nbInk : Color.nbCard))
                .overlay {
                    if !selected {
                        Capsule().stroke(Color.nbGray, lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Groups

    @ViewBuilder
    private var groupsContent: some View {
        let groups = visibleGroups
        let guests = visibleGuests

        if groups.isEmpty && guests.isEmpty {
            NBCard {
                Text("Kein Gerät passt zur Suche.")
                    .font(.nbSans(15))
                    .foregroundStyle(Color.nbMuted)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        ForEach(groups, id: \.category) { group in
            deviceGroup(group.category, devices: group.devices)
        }

        if !guests.isEmpty {
            guestSection(guests)
        }
    }

    private func deviceGroup(_ category: DeviceCategory, devices: [Device]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            groupTitle(category, count: devices.count)

            NBCard {
                VStack(spacing: 0) {
                    ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 {
                            NBRowDivider()
                        }
                        NavigationLink(value: device.id) {
                            DeviceListRow(device: device, isNew: isNew(device), isSlow: isSlow(device))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func groupTitle(_ category: DeviceCategory, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if category == .unknown {
                Text(category.title)
                    .font(.nbSerif(28))
                    .foregroundStyle(Color.nbWarn)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityAddTraits(.isHeader)
            } else {
                NBSectionTitle(category.title)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Text("\(count)")
                .font(.nbSans(14))
                .foregroundStyle(Color.nbMuted)
        }
    }

    private func guestSection(_ guests: [Device]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NBSectionTitle("Gäste")

            NBCard {
                VStack(spacing: 0) {
                    ForEach(Array(guests.enumerated()), id: \.element.id) { index, guest in
                        if index > 0 {
                            NBRowDivider()
                        }
                        NBRow(
                            symbol: guest.symbolName,
                            title: guest.name,
                            subtitle: "Abgeschottet · wird nicht ausgewertet"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Lese die Geräteliste …")
                .font(.nbSans(15))
                .foregroundStyle(Color.nbMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Row

/// Same layout as `NBRow`, but the title can be dimmed for devices that are asleep.
private struct DeviceListRow: View {
    let device: Device
    let isNew: Bool
    let isSlow: Bool

    private var subtitle: String {
        if let vendor = device.vendor, !vendor.isEmpty {
            return "\(device.connectionSummary) · \(vendor)"
        }
        return device.connectionSummary
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(device.isActive ? Color.nbTint : Color.nbLine)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: device.symbolName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(device.isActive ? Color.nbTintInk : Color.nbMuted)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.nbSans(15, weight: .semibold))
                    .foregroundStyle(device.isActive ? Color.nbInk : Color.nbInkSoft)
                Text(subtitle)
                    .font(.nbSans(13))
                    .foregroundStyle(Color.nbMuted)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if isNew {
                    NBChip("Neu", style: .warn)
                }
                if isSlow {
                    NBChip("Langsam", style: .warn)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        DevicesView()
    }
    .environment(AppModel())
}
