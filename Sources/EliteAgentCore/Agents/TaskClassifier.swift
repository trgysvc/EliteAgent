import Foundation

public enum TaskCategory: String, Codable, Sendable, CaseIterable {
    case research
    case fileProcessing
    case systemManagement
    case codeGeneration
    case dataProcessing
    case multiStepWorkflow
    case applicationAutomation
    case computerUseAX
    case conversation
    case hardware
    case status
    case other
}

public struct TaskClassifier: Sendable {
    public init() {}
    
    public func classify(prompt: String) -> TaskCategory {
        let p = prompt.lowercased()
        if p.contains("araştır") || p.contains("search") || p.contains("find") { return .research }
        if p.contains("dosya") || p.contains("file") { return .fileProcessing }
        if p.contains("kod") || p.contains("swift") || p.contains("build") { return .codeGeneration }
        if p.contains("system") || p.contains("terminal") || p.contains("shell") { return .systemManagement }
        if p.contains("json") || p.contains("veri") || p.contains("parse") { return .dataProcessing }
        if p.contains("sıcaklık") || p.contains("işlemci") || p.contains("cpu") || p.contains("gpu") || p.contains("donanım") || p.contains("hardware") || p.contains("thermal") { return .hardware }
        if p.contains("durum") || p.contains("status") || p.contains("ne durum") { return .status }
        if p.contains("farklı") || p.contains("workflow") { return .multiStepWorkflow }
        if p.contains("safari") || p.contains("xcode") || p.contains("figma") || p.contains("app") { return .applicationAutomation }
        if p.contains("tıkla") || p.contains("click") || p.contains("ekran") { return .computerUseAX }
        
        // Conversational cues
        let conversational = ["merhaba", "selam", "hello", "hi", "nasılsın", "how are you", "kimsin", "who are you"]
        if conversational.contains(where: { p.contains($0) }) { return .conversation }
        
        return .other
    }
}
