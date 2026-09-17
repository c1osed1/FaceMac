import Foundation

public struct Enrollment: Codable, Equatable {
    public var name: String
    public var embeddings: [FaceEmbedding]
    public var createdAt: Date
    /// Which embedder produced these samples; nil for pre-tag enrollments.
    public var modelTag: String?

    public init(
        name: String,
        embeddings: [FaceEmbedding],
        createdAt: Date = Date(),
        modelTag: String? = nil
    ) {
        self.name = name
        self.embeddings = embeddings
        self.createdAt = createdAt
        self.modelTag = modelTag
    }
}

/// Stores reference face embeddings on disk. Embeddings are measurements, not images.
public final class EnrollmentStore {
    public static let shared = EnrollmentStore()

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL()
    }

    public static func defaultURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("FaceMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("enrollment.json")
    }

    public func save(_ enrollment: Enrollment) throws {
        let data = try JSONEncoder().encode(enrollment)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func load() throws -> Enrollment? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Enrollment.self, from: data)
    }

    public func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
