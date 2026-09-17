import Foundation

public struct MatchResult {
    public let similarity: Float
    public let isMatch: Bool
    public let bestIndex: Int?

    public init(similarity: Float, isMatch: Bool, bestIndex: Int?) {
        self.similarity = similarity
        self.isMatch = isMatch
        self.bestIndex = bestIndex
    }
}

public enum FaceMatcher {
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for index in 0..<a.count {
            dot += a[index] * b[index]
            normA += a[index] * a[index]
            normB += b[index] * b[index]
        }
        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dot / denominator : 0
    }

    public static func match(
        _ candidate: FaceEmbedding,
        against enrolled: [FaceEmbedding],
        threshold: Float
    ) -> MatchResult {
        var best: Float = -1
        var bestIndex: Int?
        for (index, reference) in enrolled.enumerated() {
            let similarity = cosine(candidate.vector, reference.vector)
            if similarity > best {
                best = similarity
                bestIndex = index
            }
        }
        guard bestIndex != nil else {
            return MatchResult(similarity: 0, isMatch: false, bestIndex: nil)
        }
        return MatchResult(similarity: best, isMatch: best >= threshold, bestIndex: bestIndex)
    }

    public static func similarity(_ candidate: FaceEmbedding, toCentroid centroid: FaceEmbedding) -> Float {
        guard !centroid.vector.isEmpty else { return 0 }
        return cosine(candidate.vector, centroid.vector)
    }
}
