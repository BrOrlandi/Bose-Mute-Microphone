import Foundation

/// Persists pre-mute values so a crash or forced quit while muted never loses the original state.
public struct SnapshotStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var `default`: SnapshotStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bose-Mute-Microphone", isDirectory: true)
        return SnapshotStore(url: base.appendingPathComponent("mute-snapshot.json"))
    }

    public func load() -> [DeviceSnapshot] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([DeviceSnapshot].self, from: data)) ?? []
    }

    public func save(_ snapshots: [DeviceSnapshot]) {
        if snapshots.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshots) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
