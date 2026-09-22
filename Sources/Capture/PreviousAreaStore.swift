import Foundation

struct PreviousAreaStore {
    static let key = "screenshotPreviousArea"

    let defaults: UserDefaults

    func load() -> CaptureRegion? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(CaptureRegion.self, from: data)
    }

    func save(_ region: CaptureRegion) {
        guard let data = try? JSONEncoder().encode(region) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
