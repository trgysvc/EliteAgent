import Foundation

public struct ResearchReportTool: AgentTool {
    public let name = "research_report"
    public let summary = "Finalize strategic JSON research reports."
    public let description = "MANDATORY: Use this tool to finalize a strategic research task. It formats findings into a premium UI-compatible JSON report. Parametre: report_json (string)."
    public let ubid = 20 // Token '5' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let reportJson = params["report_json"]?.value as? String else {
            throw ToolError.missingParameter("report_json")
        }
        
        // Validation: Ensure it's valid JSON and contains the 'report' key
        guard let data = reportJson.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["report"] != nil else {
            throw ToolError.invalidParameter("Invalid ResearchReport JSON format. Must contain 'report' object.")
        }
        
        // Return the JSON as the final output. The OrchestratorRuntime will handle its presentation.
        return reportJson
    }
}
