import Foundation
import WeatherKit
import CoreLocation

public struct CalculatorTool: AgentTool {
    public let name = "calculator_op"
    public let summary = "Fast native arithmetic solver."
    public let description = "Perform basic math. Parametre: expression (string)."
    public let ubid = 51 // Token 'T' in Qwen 2.5
    
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
    public let summary = "WeatherDNA Core: Apple WeatherKit Rich Engine."
    public let description = "Retrieve detailed weather reports (Temperature, UV, Humidity, Wind, Moon Phase) using the native macOS WeatherKit service. Supports specific dates. Parameters: location (MANDATORY - NEVER OMIT, string), day (string, optional: e.g. '13 nisan', 'tomorrow', 'pazartesi')."
    public let ubid = 52 // Token 'U' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let locationName = params["location"]?.value as? String else {
            throw ToolError.missingParameter("location")
        }
        
        let dayParam = (params["day"]?.value as? String ?? "today").lowercased()
        
        // v14.10: WeatherDNA - Improved Date Matching
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = locationName
        request.resultTypes = .address
        
        let search = MKLocalSearch(request: request)
        let response = try? await search.start()
        
        guard let location = response?.mapItems.first?.placemark.location else {
            return "⚠️ Lokasyon bulunamadı: \(locationName). Şehir ismini kontrol edin."
        }
        
        if #available(macOS 13.0, *) {
            do {
                let weather = try await WeatherService.shared.weather(for: location)
                
                // Deterministic Date Matcher for the next 10 days
                let calendar = Calendar.current
                var targetForecast: DayWeather?
                var dateLabel = dayParam
                
                if dayParam.contains("bugün") || dayParam == "today" {
                    targetForecast = weather.dailyForecast.first
                    dateLabel = "Bugün"
                } else if dayParam.contains("yarın") || dayParam == "tomorrow" {
                    targetForecast = weather.dailyForecast.forecast.first { calendar.isDateInTomorrow($0.date) }
                    dateLabel = "Yarın"
                } else {
                    // Search in 10-day forecast for matching date string (e.g. "13 nisan" or "pazartesi")
                    targetForecast = weather.dailyForecast.forecast.first { forecast in
                        let formatter = DateFormatter()
                        formatter.locale = Locale(identifier: "tr_TR")
                        
                        // Check for weekday match
                        formatter.dateFormat = "EEEE"
                        if formatter.string(from: forecast.date).lowercased() == dayParam { return true }
                        
                        // Check for specific date match (e.g. "13 nisan")
                        formatter.dateFormat = "d MMMM"
                        if formatter.string(from: forecast.date).lowercased() == dayParam { return true }
                        
                        return false
                    }
                }
                
                // v13.8: UNO Pure - External Protocol Adaptor (No JSON logic in core)
                if let dayWeather = targetForecast {
                    let tempHigh = Int(dayWeather.highTemperature.value)
                    let tempLow  = Int(dayWeather.lowTemperature.value)
                    let condition = dayWeather.condition.description
                    let uvIndex = dayWeather.uvIndex.value
                    let uvCategory = dayWeather.uvIndex.category.description
                    let sunset = dayWeather.sun.sunset?.formatted(date: .omitted, time: .shortened) ?? "--:--"
                    let sunrise = dayWeather.sun.sunrise?.formatted(date: .omitted, time: .shortened) ?? "--:--"
                    let moonPhase = dayWeather.moon.phase.description
                    let precipitation = Int(dayWeather.precipitationChance * 100)
                    
                    return """
                    📍 \(locationName.uppercased()) - \(dateLabel.uppercased()) 🌦
                    ───────────────────────────
                    🌤 Durum: \(condition)
                    🌡 Sıcaklık: En Yüksek \(tempHigh)°C | En Düşük \(tempLow)°C
                    ───────────────────────────
                    ☀️ UV İndeksi: \(uvIndex) (\(uvCategory))
                    🌧 Yağış İhtimali: %\(precipitation)
                    🌅 Gün Doğumu: \(sunrise) | 🌇 Gün Batımı: \(sunset)
                    🌙 Ay Safhası: \(moonPhase)
                    ───────────────────────────
                    [WeatherDNA_WIDGET]
                    *(WeatherDNA Engine v14.10)*
                    """
                }
                
                // Default: Current Weather Home View
            let current = weather.currentWeather
            let daily = weather.dailyForecast.first
            
            var forecast = "📍 \(locationName.uppercased()) - BUGÜN 🌦\n"
            forecast += "───────────────────────────\n"
            forecast += "🌤 Durum: \(current.condition.description)\n"
            forecast += "🌡 Sıcaklık: \(Int(current.temperature.value))°C | Hissedilen: \(Int(current.apparentTemperature.value))°C\n"
            if let low = daily?.lowTemperature.value, let high = daily?.highTemperature.value {
                forecast += "📈 En Yüksek: \(Int(high))°C | 📉 En Düşük: \(Int(low))°C\n"
            }
            forecast += "───────────────────────────\n"
            forecast += "💧 Nem: %\(Int(current.humidity * 100)) | 🌬 Rüzgar: \(Int(current.wind.speed.value)) km/s\n"
            forecast += "🌪 Hamle: \(Int(current.wind.gust?.value ?? 0)) km/s | 🧭 Yön: \(current.wind.compassDirection.description)\n"
            forecast += "☀️ UV İndeksi: \(current.uvIndex.value) (\(current.uvIndex.category.description))\n"
            forecast += "👁 Görüş: \(Int(current.visibility.value / 1000)) km | ⏲ Basınç: \(Int(current.pressure.value)) hPa\n"
            if let rise = daily?.sun.sunrise, let set = daily?.sun.sunset {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                forecast += "🌅 Gün Doğumu: \(formatter.string(from: rise)) | 🌇 Gün Batımı: \(formatter.string(from: set))\n"
            }
            forecast += "📉 Çiy Noktası: \(Int(current.dewPoint.value))°C | 🌧 Yağış: %\(Int((daily?.precipitationChance ?? 0) * 100))\n"
            forecast += "───────────────────────────\n"
            forecast += "[WeatherDNA_WIDGET]\n"
            forecast += "*(WeatherDNA Engine v14.11 - Premium Data)*"
            
            return forecast
                
            } catch {
                AgentLogger.logAudit(level: .error, agent: "WeatherTool", message: "WeatherKit Failure: \(error.localizedDescription)")
            }
        }
        
        // v14.9 Fallback: Simplified wttr.in (Updated to match dashboard style)
        let encoded = locationName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? locationName
        let urlString = "https://wttr.in/\(encoded)?format=j1"
        
        if let url = URL(string: urlString),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let dict = UNOExternalBridge.resolveDictionary(from: data),
           let weatherArray = dict["weather"] as? [[String: Any]],
           let dayWeather = weatherArray.first,
           let hourly = (dayWeather["hourly"] as? [[String: Any]])?.first,
           let tempStr = hourly["tempC"] as? String {
            
            let desc = (hourly["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String ?? "Bilinmiyor"
            let maxC = dayWeather["maxtempC"] as? String ?? tempStr
            let minC = dayWeather["mintempC"] as? String ?? tempStr
            let humidity = hourly["humidity"] as? String ?? "--"
            let wind = hourly["windspeedKmph"] as? String ?? "--"
            
            return """
            📍 \(locationName.uppercased()) (Yedek Servis) ☁️
            ───────────────────────────
            🌤 Durum: \(desc)
            🌡 Sıcaklık: En Yüksek \(maxC)°C | En Düşük \(minC)°C
            ───────────────────────────
            💧 Nem: %\(humidity)         💨 Rüzgar: \(wind) km/s
            ───────────────────────────
            [WeatherDNA_WIDGET]
            *(WeatherDNA Fallback Mode)*
            """
        }
        
        return "⚠️ \(locationName) için hava durumu verisi alınamadı. Lütfen internet bağlantınızı veya lokasyonu kontrol edin."
    }
}

public struct TimerTool: AgentTool {
    public let name = "set_timer"
    public let summary = "Background macOS async timers."
    public let description = "Set a timer/reminder. Parametre: seconds (int), message (string)."
    public let ubid = 53 // Token 'V' in Qwen 2.5
    
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

public struct SystemInfoTool: AgentTool {
    public let name = "get_system_info"
    public let summary = "Real-time macOS CPU/RAM telemetry."
    public let description = "Retrieve current system resource usage (CPU Load, Application Memory, Active Threads). Parameters: none."
    public let ubid = 54
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        var stats = "💻 SİSTEM DURUMU\n───────────────────────────\n"
        
        // RAM Info
        var hostSize = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var vmStats = vm_statistics64()
        let hostPort = mach_host_self()
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(hostSize)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &hostSize)
            }
        }
        
        if result == KERN_SUCCESS {
            let pageSize = UInt64(getpagesize())
            let active = UInt64(vmStats.active_count) * pageSize / (1024 * 1024 * 1024)
            let free = UInt64(vmStats.free_count) * pageSize / (1024 * 1024 * 1024)
            stats += "🧠 RAM: \(active)GB Kullanımda | \(free)GB Boş\n"
        }
        
        // Logical Cores
        let cores = ProcessInfo.processInfo.activeProcessorCount
        stats += "⚙️ İşlemci: \(cores) Aktif Çekirdek\n"
        stats += "───────────────────────────\n[SystemDNA_WIDGET]\n"
        
        return stats
    }
}

public struct SystemDateTool: AgentTool {
    public let name = "get_system_date"
    public let summary = "Precise system wall-clock time."
    public let description = "Current date, time, and timezone. Parameters: none."
    public let ubid = 55
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "EEEE, d MMMM yyyy HH:mm"
        let dateString = formatter.string(from: Date())
        
        return "📅 Bugün: \(dateString)"
    }
}
