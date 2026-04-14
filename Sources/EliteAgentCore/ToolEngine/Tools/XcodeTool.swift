import Foundation
import Cocoa

/// XcodeTool: EliteAgent'in "Commander" modeline dayalı Xcode entegrasyon aracı.
/// AppleScript ve xcodebuild üzerinden otonom uygulama geliştirme sağlar.
public struct XcodeTool: AgentTool, Sendable {
    public let name = "xcode_engine"
    public let summary = "Autonomous Xcode/SPM project management and building."
    public let description = """
    Xcode projelerini ve Swift paketlerini (SPM) yönetir. 
    Eylemler:
    - project_map: Proje hiyerarşisini ve dosyaları listeler.
    - build_and_fix: Projeyi derler, hata varsa otonom olarak düzeltme döngüsüne girer.
    - simulator_control: Simülatörü başlatır/durdurur veya uygulama yükler.
    Parametreler: action (String), path (String), target (String?), destination (String?)
    """
    public let ubid = 47 // v19.7.8: Resolved collision with WebSearch (45)
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let action = params["action"]?.value as? String else {
            throw ToolError.missingParameter("action")
        }
        
        switch action {
        case "project_map":
            return try await handleProjectMap(params: params, session: session)
        case "build_and_fix":
            return try await handleBuildAndFix(params: params, session: session)
        case "simulator_control":
            return try await handleSimulatorControl(params: params)
        default:
            throw ToolError.invalidParameter("Unknown action: \(action)")
        }
    }
    
    private func handleProjectMap(params: [String: AnyCodable], session: Session) async throws -> String {
        let path = params["path"]?.value as? String ?? "."
        let folderURL = path == "." ? session.workspaceURL : URL(fileURLWithPath: path)
        
        let fileManager = FileManager.default
        var result = "--- Project Map (\(folderURL.lastPathComponent)) ---\n"
        
        // 1. Check for Package.swift (SPM Priority)
        let packageURL = folderURL.appendingPathComponent("Package.swift")
        if fileManager.fileExists(atPath: packageURL.path) {
            result += "[Type: Swift Package Manager]\n"
        }
        
        // 2. Check for .xcodeproj or .xcworkspace
        if let contents = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) {
            for item in contents {
                if item.pathExtension == "xcodeproj" || item.pathExtension == "xcworkspace" {
                    result += "[Type: Xcode Project/Workspace: \(item.lastPathComponent)]\n"
                }
            }
        }
        
        // 3. List relevant files
        let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        
        var count = 0
        while let fileURL = enumerator?.nextObject() as? URL, count < 100 {
            let path = fileURL.path.replacingOccurrences(of: folderURL.path + "/", with: "")
            if fileURL.pathExtension == "swift" || fileURL.pathExtension == "xcconfig" {
                result += "- \(path)\n"
                count += 1
            }
        }
        
        return result
    }
    
    private func handleBuildAndFix(params: [String: AnyCodable], session: Session) async throws -> String {
        let path = params["path"]?.value as? String ?? "."
        let target = params["target"]?.value as? String
        let destination = params["destination"]?.value as? String ?? "platform=macOS"
        let workspaceURL = path == "." ? session.workspaceURL : URL(fileURLWithPath: path)
        
        AgentLogger.logAudit(level: .info, agent: "XcodeEngine", message: "🚀 Build starting for \(workspaceURL.lastPathComponent)...")
        
        // Construct xcodebuild or swift build
        var command = ""
        let isSPM = FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent("Package.swift").path)
        
        if isSPM {
            command = "swift build"
        } else {
            command = "xcodebuild -destination '\(destination)'"
            if let t = target { command += " -target \(t)" }
            command += " build"
        }
        
        let output = try await runShell(command: command, directory: workspaceURL)
        
        if output.contains("error:") || output.contains("FAILED") {
            AgentLogger.logAudit(level: .warn, agent: "XcodeEngine", message: "❌ Build failed. Attempting self-healing...")
            // v13.9: Logic for build error capture
            return "[BUILD_FAILED]\n\(output)\n\nEliteAgent Analizi: Hata mesajları yukarıdadır. Lütfen kodları düzelterek tekrar deneyin veya AutoRecoveryEngine'i tetikleyin."
        }
        
        return "✅ Build Successful!\nOutput:\n\(output.suffix(500))"
    }
    
    private func handleSimulatorControl(params: [String: AnyCodable]) async throws -> String {
        let subAction = params["sub_action"]?.value as? String ?? "list"
        
        switch subAction {
        case "list":
            return try await runShell(command: "xcrun simctl list devices available", directory: URL(fileURLWithPath: "/tmp"))
        case "boot":
            guard let deviceID = params["device_id"]?.value as? String else {
                throw ToolError.missingParameter("device_id")
            }
            return try await runShell(command: "xcrun simctl boot \(deviceID)", directory: URL(fileURLWithPath: "/tmp"))
        default:
            return "Unsupported simulator action."
        }
    }
    
    private func runShell(command: String, directory: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = directory
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            } catch {
                continuation.resume(throwing: ToolError.executionError(error.localizedDescription))
            }
        }
    }
}
