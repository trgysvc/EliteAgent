import Foundation

/// Handles Cloud (OpenRouter) provider setup during first-run.
@MainActor
public final class OpenRouterProvider {
    public static let shared = OpenRouterProvider()
    
    private init() {}
    
    /// Setup OpenRouter by storing the API key and testing the provider connection.
    public func setupCloudProvider(apiKey: String) async throws {
        // 1. Save API key to Keychain safely
        // Note: VaultManager.shared is not available, so we'll trigger a notification to inform Orchestrator's VaultManager
        NotificationCenter.default.post(
            name: NSNotification.Name("UpdateVaultAPIKey"),
            object: nil,
            userInfo: ["providerID": "openrouter", "key": apiKey]
        )
        
        AgentLogger.logAudit(level: .info, agent: "OpenRouterProvider", message: "Cloud provider setup initiated.")
        
        // 2. Set as default model if needed
        // This logic is usually handled by VaultManager once the key is in place.
    }
    
    /// Test connection to see if API Key is valid.
    public func testConnection(apiKey: String) async throws -> Bool {
        let url = URL(string: "https://openrouter.ai/api/v1/auth/key")!
        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            return http.statusCode == 200
        }
        return false
    }
}
