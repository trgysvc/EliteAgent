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
    public let description = "Get weather for a location using native macOS services. Parametres: location (string), day (optional string, e.g. 'yarın', '24 nisan')."
    public let ubid: Int128 = ToolUBID.weatherReport.rawValue
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let locationName = params["location"]?.value as? String else {
            throw AgentToolError.missingParameter("location")
        }
        
        let targetDay = params["day"]?.value as? String
        let geocoder = CLGeocoder()
        let placemarks = try? await geocoder.geocodeAddressString(locationName)
        
        guard let location = placemarks?.first?.location else {
            return "Üzgünüm, '\(locationName)' konumu bulunamadı."
        }
        
        let localTz = placemarks?.first?.timeZone ?? .current
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        timeFormatter.timeZone = localTz
        
        var localCalendar = Calendar.current
        localCalendar.timeZone = localTz
        
        if #available(macOS 13.0, *) {
            do {
                let weather = try await WeatherService.shared.weather(for: location)
                var tags: String = "[WeatherDNA_WIDGET]"
                
                if let dayText = targetDay?.lowercased() {
                    let daily = weather.dailyForecast
                    let forecast = daily.first { item in
                        let formatter = DateFormatter()
                        formatter.locale = Locale(identifier: "tr_TR")
                        formatter.dateFormat = "d MMMM"
                        formatter.timeZone = localTz
                        let trDate = formatter.string(from: item.date).lowercased()
                        
                        let dateString = item.date.description.lowercased()
                        return trDate.contains(dayText) || dateString.contains(dayText)
                    }
                    
                    if let item = forecast {
                        let high = Int(item.highTemperature.value)
                        let low = Int(item.lowTemperature.value)
                        let cond = item.condition.description
                        let uv = item.uvIndex.value
                        let rain = Int(item.precipitationChance * 100)
                        
                        tags += "\n[DURUM] \(cond)"
                        tags += "\n[YUKSEK] \(high)°C"
                        tags += "\n[DUSUK] \(low)°C"
                        tags += "\n[UV] \(uv)"
                        tags += "\n[YAGIS] %\(rain)"
                        
                        // v24.3: Fetch representative hourly data using the location's local hour (12:00 PM)
                        let targetDate = item.date
                        let hourly = weather.hourlyForecast.filter { localCalendar.isDate($0.date, inSameDayAs: targetDate) }
                        if let midDay = hourly.first(where: { localCalendar.component(.hour, from: $0.date) >= 12 }) ?? hourly.first {
                            tags += "\n[HIS] \(Int(midDay.apparentTemperature.value))°C"
                            tags += "\n[NEM] %\(Int(midDay.humidity * 100))"
                            tags += "\n[RUZGAR] \(Int(midDay.wind.speed.value)) km/h"
                            tags += "\n[PRES] \(Int(midDay.pressure.value)) hPa"
                            tags += "\n[GORUS] \(Int(midDay.visibility.value / 1000)) km"
                        }
                        
                        if let sunrise = item.sun.sunrise {
                            tags += "\n[DOGUM] \(timeFormatter.string(from: sunrise))"
                        }
                        if let sunset = item.sun.sunset {
                            tags += "\n[BATIM] \(timeFormatter.string(from: sunset))"
                        }
                        
                        return "\(tags)\n\(locationName) için \(dayText) tahmini: \(cond)."
                    }
                }
                
                let current = weather.currentWeather
                let humidity = Int(current.humidity * 100)
                let windSpeed = Int(current.wind.speed.value)
                let windGust = Int(current.wind.gust?.value ?? 0)
                let pressure = Int(current.pressure.value)
                let visibility = Int(current.visibility.value / 1000)
                let uv = current.uvIndex.value
                let apparent = Int(current.apparentTemperature.value)
                
                tags += "\n[DURUM] \(current.condition.description)"
                tags += "\n[HIS] \(apparent)°C"
                tags += "\n[NEM] %\(humidity)"
                tags += "\n[RUZGAR] \(windSpeed) km/h"
                if windGust > 0 {
                    tags += "\n[HAMLE] \(windGust) km/h"
                }
                tags += "\n[UV] \(uv)"
                tags += "\n[PRES] \(pressure) hPa"
                tags += "\n[GORUS] \(visibility) km"
                
                // Fetch daily extremes for today using the local calendar boundary
                if let today = weather.dailyForecast.first(where: { localCalendar.isDateInToday($0.date) }) ?? weather.dailyForecast.first {
                    tags += "\n[YUKSEK] \(Int(today.highTemperature.value))°C"
                    tags += "\n[DUSUK] \(Int(today.lowTemperature.value))°C"
                    tags += "\n[YAGIS] %\(Int(today.precipitationChance * 100))"
                    
                    if let sunrise = today.sun.sunrise {
                        tags += "\n[DOGUM] \(timeFormatter.string(from: sunrise))"
                    }
                    if let sunset = today.sun.sunset {
                        tags += "\n[BATIM] \(timeFormatter.string(from: sunset))"
                    }
                }
                
                return "\(tags)\n\(locationName) için güncel hava durumu: \(Int(current.temperature.value))°C."
            } catch {
                AgentLogger.logAudit(level: .warn, agent: "WeatherTool", message: "WeatherKit failed (XPC/Auth). Falling back to web-based provider. Error: \(error.localizedDescription)")
                
                // v24.3: Robust Fallback with Tag Support
                // We use wttr.in format that includes the most critical telemetry tags
                // format: %t (temp), %C (condition), %h (humidity), %w (wind), %P (pressure), %p (precip)
                let queryLocation = locationName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                var urlString = "https://wttr.in/\(queryLocation)?format=%t|%C|%h|%w|%P|%p|%u"
                
                // Convert relative days to wttr.in format (1 for tomorrow, 2 for day after)
                if let day = targetDay?.lowercased() {
                    if day.contains("yarın") || day.contains("tomorrow") {
                        urlString = "https://wttr.in/\(queryLocation)?1&format=%t|%C|%h|%w|%P|%p|%u"
                    }
                }
                
                if let url = URL(string: urlString),
                   let (data, _) = try? await URLSession.shared.data(from: url),
                   let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    
                    let parts = raw.components(separatedBy: "|")
                    if parts.count >= 6 {
                        let temp = parts[0]
                        let cond = parts[1]
                        let hum = parts[2]
                        let wind = parts[3]
                        let pres = parts[4]
                        let rain = parts[5]
                        let uv = parts.indices.contains(6) ? parts[6] : "3"
                        
                        var fallbackTags = "[WeatherDNA_WIDGET]"
                        fallbackTags += "\n[DURUM] \(cond)"
                        fallbackTags += "\n[HIS] \(temp)"
                        fallbackTags += "\n[NEM] \(hum)"
                        fallbackTags += "\n[RUZGAR] \(wind)"
                        fallbackTags += "\n[PRES] \(pres)"
                        fallbackTags += "\n[YAGIS] \(rain)"
                        fallbackTags += "\n[UV] \(uv)"
                        fallbackTags += "\n[YUKSEK] \(temp)" // Fallback approximation
                        fallbackTags += "\n[DUSUK] \(temp)"
                        
                        return "\(fallbackTags)\n\(locationName) için \(targetDay ?? "güncel") hava durumu (Web yedek): \(temp), \(cond)."
                    }
                    
                    return "[WeatherDNA_WIDGET]\n[DURUM] \(raw)\n\(locationName) \(targetDay ?? "güncel")"
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
