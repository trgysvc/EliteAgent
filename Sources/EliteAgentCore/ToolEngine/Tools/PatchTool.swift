import Foundation

public struct PatchTool: AgentTool, Sendable {
    public let name = "patch_file"
    public let summary = "Atomic hot-patch for code snippets."
    public let description = "Atomically patches an existing file by exactly matching 'old_content' and replacing it with 'new_content'. Do NOT use sed/awk."
    public let ubid = 41 // Token 'J' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let path = params["path"]?.value as? String else {
            throw ToolError.missingParameter("path")
        }
        guard let oldContent = params["old_content"]?.value as? String else {
            throw ToolError.missingParameter("old_content")
        }
        guard let newContent = params["new_content"]?.value as? String else {
            throw ToolError.missingParameter("new_content")
        }
        
        let fileURL: URL
        if path.hasPrefix("file://") {
            fileURL = URL(string: path)!
        } else if path.hasPrefix("/") || path.hasPrefix("~") {
            let expandedPath = NSString(string: path).expandingTildeInPath
            fileURL = URL(fileURLWithPath: expandedPath)
        } else {
            fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path)
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ToolError.executionError("File does not exist: \(fileURL.path)")
        }
        
        var originalText = try String(contentsOf: fileURL, encoding: .utf8)
        
        // Count occurrences to ensure we only patch if there's exactly one match,
        // to avoid ambiguous patching.
        func countOccurrences(of substring: String, in string: String) -> Int {
            var count = 0
            var range = string.startIndex..<string.endIndex
            while let r = string.range(of: substring, range: range) {
                count += 1
                range = r.upperBound..<string.endIndex
            }
            return count
        }
        
        let matchCount = countOccurrences(of: oldContent, in: originalText)
        
        if matchCount == 0 {
            throw ToolError.executionError("Target snippet 'old_content' NOT FOUND in the file! (Please make sure whitespace matches perfectly).")
        }
        if matchCount > 1 {
            throw ToolError.executionError("Target snippet 'old_content' matches MULTIPLE times (\(matchCount) matches). Context is ambiguous, please provide a larger unique block or use full write_file.")
        }
        
        originalText = originalText.replacingOccurrences(of: oldContent, with: newContent)
        
        try originalText.write(to: fileURL, atomically: true, encoding: .utf8)
        
        return "SUCCESS: File patched securely (\(fileURL.lastPathComponent))."
    }
}
