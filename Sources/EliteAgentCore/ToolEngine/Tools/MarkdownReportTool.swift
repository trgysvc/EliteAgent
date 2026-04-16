import Foundation

public struct MarkdownReportTool: AgentTool {
    public let name = "research_report"
    public let summary = "Finalize strategic research reports (Markdown)."
    public let description = "MANDATORY: Use this tool to finalize a strategic research task. It formats findings into a premium UI-compatible Markdown section. Parametre: report_markdown (string)."
    public let ubid = 20 
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let markdownContent = params["report_markdown"]?.value as? String else {
            throw AgentToolError.missingParameter("report_markdown")
        }
        
        // UNO Pure: Strictly Markdown-based reporting. No JSON wrappers.
        AgentLogger.logInfo("[UNO-Pure] Strategic Research Report finalized via Markdown.")
        
        return markdownContent
    }
}
