import Foundation

public struct ModelMetrics: Codable, Sendable {
    public var promptTokens: Int = 0
    public var completionTokens: Int = 0
    public var totalCost: Decimal = 0
    
    public init(promptTokens: Int = 0, completionTokens: Int = 0, totalCost: Decimal = 0) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalCost = totalCost
    }
}

public actor MetricsStore {
    public static let shared = MetricsStore()
    
    private let fileURL: URL
    private var metrics: [String: ModelMetrics] = [:]
    
    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        fileURL = home.appendingPathComponent(".eliteagent/metrics.json")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        // Load initial data
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: ModelMetrics].self, from: data) {
            self.metrics = decoded
        }
    }
    
    private func save() {
        guard let data = try? JSONEncoder().encode(metrics) else { return }
        try? data.write(to: fileURL)
    }
    
    public func update(modelID: String, promptTokens: Int, completionTokens: Int, cost: Decimal) {
        var current = metrics[modelID] ?? ModelMetrics()
        current.promptTokens += promptTokens
        current.completionTokens += completionTokens
        current.totalCost += cost
        metrics[modelID] = current
        save()
    }
    
    public func getMetrics() -> [String: ModelMetrics] {
        return metrics
    }
    
    public func getTotalCost() -> Decimal {
        return metrics.values.reduce(0) { $0 + $1.totalCost }
    }
    
    public func reset() {
        metrics = [:]
        save()
    }
}
