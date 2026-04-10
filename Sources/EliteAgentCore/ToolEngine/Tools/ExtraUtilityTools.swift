import Foundation
import WeatherKit
import CoreLocation

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

import MapKit

public struct WeatherTool: AgentTool {
    public let name = "get_weather"
    public let description = "Get weather for a location using native macOS services. Parametre: location (string)."
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let locationName = params["location"]?.value as? String else {
            throw ToolError.missingParameter("location")
        }
        
        // v13.8: Using modern MapKit geocoding (macOS 15 standard)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = locationName
        request.resultTypes = .address
        
        let search = MKLocalSearch(request: request)
        let response = try? await search.start()
        
        guard let location = response?.mapItems.first?.placemark.location else {
            return "Üzgünüm, '\(locationName)' konumu bulunamadı (MapKit)."
        }
        
        if #available(macOS 13.0, *) {
            do {
                let weather = try await WeatherService.shared.weather(for: location)
                let current = weather.currentWeather
                let temp = Int(current.temperature.value)
                let condition = current.condition.description
                
                return "\(locationName) için gerçek zamanlı hava durumu: \(temp)°C, \(condition)."
            } catch {
                AgentLogger.logAudit(level: .warn, agent: "WeatherTool", message: "WeatherKit failed (\(error.localizedDescription)). Falling back to web-based provider.")
                
                // v11.1 Fallback: Use wttr.in for reliability when WeatherKit entitlements are not fully propagated
                let urlString = "https://wttr.in/\(locationName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")?format=%t+%C"
                if let url = URL(string: urlString),
                   let data = try? await URLSession.shared.data(from: url).0,
                   let weatherInfo = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    return "\(locationName) için hava durumu (Yedek Servis): \(weatherInfo)"
                }
                
                return "macOS sisteminden hava durumu bilgisi alınamadı: \(error.localizedDescription)"
            }
        } else {
            return "Hava durumu servisi için macOS 13.0 veya üzeri gereklidir."
        }
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
        
        // v11.0: Native macOS async timer task
        Task {
            AgentLogger.logAudit(level: .info, agent: "TimerTool", message: "Timer started for \(seconds) seconds: \(message)")
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            AgentLogger.logAudit(level: .info, agent: "TimerTool", message: "🚀 Timer triggered: \(message)")
        }
        
        return "\(seconds) saniyelik zamanlayıcı ayarlandı."
    }
}
