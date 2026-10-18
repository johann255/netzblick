import Foundation

/// Location of data shared between the app and its widgets.
public enum SharedContainer {
    public static let appGroupID = "group.com.johann255.netzblick"
    public static let summaryFileName = "widget-summary.json"
    /// Widget kind identifiers, used by the app to reload specific widgets.
    public static let statusWidgetKind = "NetzblickStatus"
    public static let overviewWidgetKind = "NetzblickOverview"
    public static let speedWidgetKind = "NetzblickSpeed"

    /// URL of the widget summary inside the App Group, or nil if the group is not configured.
    public static func summaryURL(fileManager: FileManager = .default) -> URL? {
        #if canImport(Darwin)
        return fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(summaryFileName)
        #else
        return nil
        #endif
    }

    /// Store pointed at the App Group, falling back to the caches directory (e.g. in previews).
    public static func summaryStore(fileManager: FileManager = .default) -> WidgetSummaryStore {
        let url = summaryURL(fileManager: fileManager)
            ?? fileManager.temporaryDirectory.appendingPathComponent(summaryFileName)
        return WidgetSummaryStore(fileURL: url)
    }
}
