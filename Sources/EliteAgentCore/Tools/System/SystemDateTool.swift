import Foundation

/// A tool that provides the current system date and time.
/// This prevents the LLM from hallucinating dates based on its training data.
public struct SystemDateTool: AgentTool {
    public let name = "get_system_time"
    public let summary = "Sistem tarihini ve saatini döner."
    public let description = "Returns the current system date, time, and day of the week. Use this whenever the user asks about the current date or time."
    public let ubid = 191 // Unique Binary ID
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        
        let now = Date()
        let dateString = formatter.string(from: now)
        
        return "GÜNCEL SİSTEM ZAMANI: \(dateString)"
    }
}
