@preconcurrency import NaturalLanguage

public final class EmbeddingService: @unchecked Sendable {
    public static let shared = EmbeddingService()
    
    private let embedding: NLEmbedding?
    
    private init() {
        self.embedding = NLEmbedding.sentenceEmbedding(for: .english)
    }
    
    public func getVector(for text: String) -> [Float]? {
        guard let embedding = embedding,
              let vector = embedding.vector(for: text) else { return nil }
        return vector.map { Float($0) }
    }
    
    public func distance(v1: [Float], v2: [Float]) -> Double? {
        // NLEmbedding uses different vector sizes depending on the model, but usually fixed
        guard v1.count == v2.count else { return nil }
        // Simple Euclidean distance or cosine is fine
        var sum: Float = 0
        for i in 0..<v1.count {
            sum += pow(v1[i] - v2[i], 2)
        }
        return Double(sqrt(sum))
    }
}
