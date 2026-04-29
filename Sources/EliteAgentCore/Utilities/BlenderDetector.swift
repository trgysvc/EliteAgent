import Foundation

/// BlenderDetector: Sistemde Blender'ın kurulu olup olmadığını tespit eder.
/// Birden fazla olası yol kontrol edilir (App Store, Homebrew, el ile kurulum).
public struct BlenderDetector: Sendable {
    
    /// Bilinen Blender kurulum yolları (macOS)
    private static let knownPaths: [String] = [
        "/Applications/Blender.app/Contents/MacOS/Blender",
        "/opt/homebrew/bin/blender",
        "/usr/local/bin/blender"
    ]
    
    /// Sistemdeki ilk bulunan Blender çalıştırılabilir dosya yolu
    public static var executablePath: String? {
        for path in knownPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    /// Blender yüklü mü?
    public static var isInstalled: Bool {
        return executablePath != nil
    }
    
    /// Blender sürüm bilgisini döndürür (headless çağrı ile)
    public static func version() async throws -> String {
        guard let path = executablePath else {
            throw AgentToolError.executionError("Blender is not installed on this system. Install from https://www.blender.org/download/")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Suppress stderr
        
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                do {
                    let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
                    guard let output = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                          !output.isEmpty else {
                        continuation.resume(throwing: AgentToolError.executionError("Could not read Blender version from stdout."))
                        return
                    }
                    let firstLine = output.components(separatedBy: "\n").first ?? output
                    continuation.resume(returning: firstLine)
                } catch {
                    continuation.resume(throwing: AgentToolError.executionError("Failed to read Blender version: \(error.localizedDescription)"))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: AgentToolError.executionError("Failed to launch Blender: \(error.localizedDescription)"))
            }
        }
    }
}
