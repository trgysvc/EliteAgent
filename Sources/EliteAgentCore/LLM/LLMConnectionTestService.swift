import Foundation

public enum ConnectionTestResult: Sendable {
    case success(modelName: String)
    case failure(error: String)
}

public actor LLMConnectionTestService {
    public init() {}
    
    public func testConnection(baseURL: URL, apiKey: String?, modelID: String) async -> ConnectionTestResult {
        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let body: [String: Any] = [
            "model": modelID,
            "messages": [
                ["role": "user", "content": "hi"]
            ],
            "max_tokens": 1
        ]
        
        // v13.8: UNO Pure - Shielded Protocol Adaptor (No JSON in internal logic)
        guard let httpBody = UNOExternalBridge.prepareExternalBlob(from: body) else {
            return .failure(error: "Protocol encoding failure")
        }
        
        do {
            request.httpBody = httpBody
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(error: "Invalid response type")
            }
            
            if httpResponse.statusCode == 200 {
                // v13.8: UNO Pure - Delegate parsing to bridge
                if let dict = UNOExternalBridge.resolveDictionary(from: data),
                   let model = dict["model"] as? String {
                    return .success(modelName: model)
                }
                return .success(modelName: modelID)
            } else {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Status code: \(httpResponse.statusCode)"
                return .failure(error: "Server returned error: \(errorMsg)")
            }
        } catch {
            return .failure(error: "Connection failed: \(error.localizedDescription)")
        }
    }
}
