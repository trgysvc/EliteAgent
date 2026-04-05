import Foundation

public struct CalculatorTool: AgentTool {
    public let name = "calculator_op"
    public let description = "Perform basic math. Parametre: expression (string)."
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let expression = params["expression"]?.value as? String else {
            throw ToolError.missingParameter("expression")
        }
        
        let format = NSExpression(format: expression)
        if let result = format.expressionValue(with: nil, context: nil) as? NSNumber {
            return "\(result.doubleValue)"
        }
        return "Calculation error."
    }
}

public struct WeatherTool: AgentTool {
    public let name = "get_weather"
    public let description = "Get weather for a location. Parametre: location (string)."
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let _ = params["location"]?.value as? String else {
            throw ToolError.missingParameter("location")
        }
        
        return "Not implemented: Weather require API Keys (WeatherKit). (Mock: İstanbul - 21°C - Sunny)"
    }
}

public struct TimerTool: AgentTool {
    public let name = "set_timer"
    public let description = "Set a timer/reminder. Parametre: seconds (int), message (string)."
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let seconds = params["seconds"]?.value as? Int else {
            throw ToolError.missingParameter("seconds")
        }
        
        let message = params["message"]?.value as? String ?? "Timer finished!"
        
        // v9.5 Mock implementation for timer:
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            print("🚀 Timer finished: \(message)")
        }
        
        return "\(seconds) saniyelik zamanlayıcı ayarlandı."
    }
}
