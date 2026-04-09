import WeatherKit
import CoreLocation
import Foundation

@available(macOS 13.0, *)
func getWeather() async {
    let weatherService = WeatherService.shared
    let location = CLLocation(latitude: 39.9334, longitude: 32.8597) // Ankara
    
    do {
        let weather = try await weatherService.weather(for: location)
        print("Temp: \(weather.currentWeather.temperature)")
        print("Condition: \(weather.currentWeather.condition)")
    } catch {
        print("Error: \(error)")
    }
}

if #available(macOS 13.0, *) {
    let task = Task {
        await getWeather()
        exit(0)
    }
    RunLoop.main.run()
} else {
    print("WeatherKit requires macOS 13+")
}
