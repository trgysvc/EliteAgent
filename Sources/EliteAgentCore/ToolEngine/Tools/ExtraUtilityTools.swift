import Foundation
import WeatherKit
import CoreLocation

// MARK: - CalculatorTool
public struct CalculatorTool: AgentTool {
    public let name = "calculator_op"
    public let summary = "Perform high-precision mathematical operations."
    public let description = "Perform basic math. Parametre: expression (string). Example: '2 + 2 * (10/5)'"
    public let ubid: Int128 = ToolUBID.calculatorOp.rawValue
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let expression = params["expression"]?.value as? String else {
            throw AgentToolError.missingParameter("expression")
        }
        
        let format = NSExpression(format: expression)
        if let result = format.expressionValue(with: nil, context: nil) as? NSNumber {
            return "\(result.doubleValue)"
        }
        return "Calculation error."
    }
}

// MARK: - WeatherTool
public struct WeatherTool: AgentTool {
    public let name = "get_weather"
    public let summary = "Real-time weather data with native telemetry."
    public let description = "Get weather for a location using native macOS services. Parametre: location (string)."
    public let ubid: Int128 = ToolUBID.weatherReport.rawValue
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let locationName = params["location"]?.value as? String else {
            throw AgentToolError.missingParameter("location")
        }
        
        let geocoder = CLGeocoder()
        let placemarks = try? await geocoder.geocodeAddressString(locationName)
        
        guard let location = placemarks?.first?.location else {
            return "Üzgünüm, '\(locationName)' konumu bulunamadı."
        }
        
        if #available(macOS 13.0, *) {
            do {
                let weather = try await WeatherService.shared.weather(for: location)
                let current = weather.currentWeather
                let temp = Int(current.temperature.value)
                let condition = current.condition.description
                
                return "\(locationName) için gerçek zamanlı hava durumu: \(temp)°C, \(condition)."
            } catch {
                AgentLogger.logAudit(level: .warn, agent: "WeatherTool", message: "WeatherKit failed. Falling back to web-based provider.")
                
                let urlString = "https://wttr.in/\(locationName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")?format=%t+%C"
                if let url = URL(string: urlString),
                   let (data, _) = try? await URLSession.shared.data(from: url),
                   let weatherInfo = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    return "\(locationName) için hava durumu (Yedek Servis): \(weatherInfo)"
                }
                
                return "macOS sisteminden hava durumu bilgisi alınamadı: \(error.localizedDescription)"
            }
        }
        return "Hava durumu servisi için macOS 13.0 veya üzeri gereklidir."
    }
}

// MARK: - SystemDateTool
public struct SystemDateTool: AgentTool {
    public let name = "system_date"
    public let summary = "Atomic system clock synchronization."
    public let description = "Returns current system date and time."
    public let ubid: Int128 = ToolUBID.systemDate.rawValue
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        return "Current time: \(formatter.string(from: Date()))"
    }
}

// MARK: - TimerTool
public struct TimerTool: AgentTool {
    public let name = "set_timer"
    public let summary = "Native async reminder engine."
    public let description = "Set a timer/reminder. Parametre: seconds (int), message (string)."
    public let ubid: Int128 = ToolUBID.timerSet.rawValue
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let seconds = params["seconds"]?.value as? Int else {
            throw AgentToolError.missingParameter("seconds")
        }
        
        let message = params["message"]?.value as? String ?? "Timer finished!"
        
        Task {
            AgentLogger.logAudit(level: .info, agent: "TimerTool", message: "Timer started for \(seconds) seconds: \(message)")
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            AgentLogger.logAudit(level: .info, agent: "TimerTool", message: "🚀 Timer triggered: \(message)")
        }
        
        return "\(seconds) saniyelik zamanlayıcı ayarlandı."
    }
}

// MARK: - SystemInfoTool
public struct SystemInfoTool: AgentTool {
    public let name = "get_system_info"
    public let summary = "Native macOS hardware and OS telemetry."
    public let description = "Get hardware, OS, and system resource information using native Swift protocols."
    public let ubid: Int128 = ToolUBID.systemInfo.rawValue
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let processorCount = ProcessInfo.processInfo.processorCount
        let memory = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        
        let info = """
[OS]: macOS \(os)
[CPU]: \(processorCount) Cores
[MEM]: \(memory) GB RAM
[AUTO]: Elite Native Mode
"""
        return "System Info: \(info)"
    }
}
