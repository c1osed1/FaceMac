import Foundation

public extension Enrollment {
    /// Mean of the reference embeddings, L2-normalised. Comparing against the
    /// centroid is stricter than taking the best of many references, which is
    /// what lets a stranger slip through.
    var centroid: FaceEmbedding {
        guard let first = embeddings.first else {
            return FaceEmbedding(vector: [])
        }
        var sum = [Float](repeating: 0, count: first.vector.count)
        var usable = 0
        for embedding in embeddings where embedding.vector.count == sum.count {
            usable += 1
            for index in 0..<sum.count {
                sum[index] += embedding.vector[index]
            }
        }
        guard usable > 0 else { return FaceEmbedding(vector: []) }
        return FaceEmbedding(vector: LandmarkEmbedder.l2Normalize(sum))
    }

    /// Mean cosine similarity between distinct reference samples.
    var selfSimilarity: Float {
        let pairs = pairwiseSimilarities
        guard !pairs.isEmpty else { return 0 }
        return pairs.reduce(0, +) / Float(pairs.count)
    }

    /// Cosine similarity for every distinct pair of reference samples.
    var pairwiseSimilarities: [Float] {
        guard embeddings.count >= 2 else { return [] }
        var values: [Float] = []
        values.reserveCapacity(embeddings.count * (embeddings.count - 1) / 2)
        for i in 0..<embeddings.count {
            for j in (i + 1)..<embeddings.count {
                values.append(FaceMatcher.cosine(embeddings[i].vector, embeddings[j].vector))
            }
        }
        return values
    }
}

public enum ThresholdCalibration {
    public struct Result {
        public let threshold: Float
        public let selfSimilarity: Float
    }

    /// Picks an accept threshold from the spread of the enrolled samples.
    ///
    /// Uses the *median* pairwise similarity: guided enrollment deliberately
    /// captures different head poses, so a few pairs are naturally less similar
    /// and a mean would drag the threshold down.
    public static func calibrate(from enrollment: Enrollment) -> Result {
        let pairs = enrollment.pairwiseSimilarities.sorted()
        let median: Float = pairs.isEmpty ? 0 : pairs[pairs.count / 2]
        let raw = median - 0.12
        let clamped = min(max(raw, 0.40), 0.65)
        return Result(threshold: clamped, selfSimilarity: enrollment.selfSimilarity)
    }
}
