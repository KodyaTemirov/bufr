import Foundation
import GRDB

struct ExcludedApp: Identifiable, Equatable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "excluded_apps"

    var bundleId: String
    var appName: String

    var id: String { bundleId }

    init(bundleId: String, appName: String) {
        self.bundleId = bundleId
        self.appName = appName
    }

    enum CodingKeys: String, CodingKey {
        case bundleId = "bundle_id"
        case appName = "app_name"
    }
}
