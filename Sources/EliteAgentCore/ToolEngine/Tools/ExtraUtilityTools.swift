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
                
                // If we found a specific day, return rich dashboard for that day
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
                let temp = Int(current.temperature.value)
                let feels = Int(current.apparentTemperature.value)
                let humidity = Int(current.humidity * 100)
                let pressure = Int(current.pressure.value)
                let visibility = Int(current.visibility.value / 1000)
                let windSpeed = Int(current.wind.speed.value)
                let windDir = current.wind.direction.description
                
                return """
                📍 \(locationName.uppercased()) - ŞİMDİ 🌡
                ───────────────────────────
                🌤 Durum: \(current.condition.description)
                🌡 Sıcaklık: \(temp)°C (Hissedilen: \(feels)°C)
                ───────────────────────────
                💧 Nem: %\(humidity)         💨 Rüzgar: \(windSpeed) km/s (\(windDir))
                ☀️ UV İndeksi: \(current.uvIndex.value)  👁 Görüş: \(visibility) km
                ⏲ Basınç: \(pressure) hPa
                ───────────────────────────
                [WeatherDNA_WIDGET]
                *(WeatherDNA Engine v14.10)*
                """
                
            } catch {
                AgentLogger.logAudit(level: .error, agent: "WeatherTool", message: "WeatherKit Failure: \(error.localizedDescription)")
            }
        }
        
        // v14.9 Fallback: Simplified wttr.in (Updated to match dashboard style)
        let encoded = locationName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? locationName
        let urlString = "https://wttr.in/\(encoded)?format=j1"
        
        if let url = URL(string: urlString),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let weatherArray = json["weather"] as? [[String: Any]],
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
