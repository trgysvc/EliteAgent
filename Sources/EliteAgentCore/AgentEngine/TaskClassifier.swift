import Foundation

public struct TaskClassifier: Sendable {
    public init() {}
    
    public func classify(prompt: String) -> TaskCategory {
        let p = prompt.lowercased()
        
        // v14.8: Hardware/Telemetry check has HIGHEST PRIORITY to avoid shell_exec fallback.
        if p.contains("cpu") || p.contains("bellek") || p.contains("ram") || p.contains("boş bellek")
            || p.contains("memory") || p.contains("telemetry") || p.contains("işlemci")
            || p.contains("donanım") || p.contains("hardware") || p.contains("thermal")
            || p.contains("gpu") {
            return .hardware
        }
        
        // v14.9: Weather MUST come before 'durum/status' because "hava durumu" contains "durum".
        // Also catches: "bugün"/"yarın" + location patterns, "forecast", "derece", "°c".
        if p.contains("hava") || p.contains("derece") || p.contains("forecast") 
            || p.contains("weather") || p.contains("yağmur") || p.contains("kar yağ")
            || p.contains("sıcaklık") {
            return .weather
        }
        
        if p.contains("araştır") || p.contains("search") || p.contains("find") { return .research }
        
        // v14.9.1: Audio Intelligence Deep Integration
        if p.contains("müzik") || p.contains("ses") || p.contains("audio") || p.contains("music")
            || p.contains(".mp3") || p.contains(".wav") || p.contains(".m4a") || p.contains(".flac") {
            return .audioAnalysis
        }
        
        if p.contains("dosya") || p.contains("file") { return .fileProcessing }
        if p.contains("kod") || p.contains("swift") || p.contains("build") { return .codeGeneration }
        if p.contains("system") || p.contains("terminal") || p.contains("shell") { return .systemManagement }
        if p.contains("json") || p.contains("veri") || p.contains("parse") { return .dataProcessing }
        if p.contains("durum") || p.contains("status") || p.contains("ne durum") { return .status }
        if p.contains("workflow") { return .multiStepWorkflow }
        if p.contains("safari") || p.contains("xcode") || p.contains("figma") { return .applicationAutomation }
        if p.contains("tıkla") || p.contains("click") { return .computerUseAX }
        if p.contains("whatsapp") || p.contains("mesaj") || p.contains("gönder") || p.contains("ileti") || p.contains("send message") { return .applicationAutomation }
        
        return .other
    }
}
