import Foundation

/// BlenderSandbox: Blender operasyonları için güvenlik katmanı.
/// Tüm dosya çıktıları ~/Documents/EliteAgentWorkspace/Blender/ altına sınırlandırılır.
/// Path traversal saldırıları engellenir.
public struct BlenderSandbox: Sendable {
    
    /// Sandbox kök dizini
    public let workspaceURL: URL
    
    /// Geçici script dosyaları için alt dizin
    public let scriptsURL: URL
    
    /// Render çıktıları için alt dizin
    public let outputsURL: URL
    
    public init() throws {
        let documentURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        self.workspaceURL = documentURL.appendingPathComponent("EliteAgentWorkspace/Blender", isDirectory: true)
        self.scriptsURL = workspaceURL.appendingPathComponent("_scripts", isDirectory: true)
        self.outputsURL = workspaceURL.appendingPathComponent("outputs", isDirectory: true)
        
        // Dizinleri oluştur (yoksa)
        let fm = FileManager.default
        for dir in [workspaceURL, scriptsURL, outputsURL] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            }
        }
    }
    
    /// Verilen dosya adının sandbox sınırları içinde kalıp kalmadığını doğrular.
    /// Path traversal (../../) saldırılarını engeller.
    public func resolvePath(for filename: String, in subdir: URL? = nil) throws -> String {
        let baseDir = subdir ?? outputsURL
        let fileURL = baseDir.appendingPathComponent(filename)
        
        // Standardize ederek '..' gibi bileşenleri çözümle
        let standardizedBase = baseDir.standardizedFileURL.path
        let standardizedFile = fileURL.standardizedFileURL.path
        
        guard standardizedFile.hasPrefix(standardizedBase) else {
            throw AgentToolError.executionError(
                "[SANDBOX VIOLATION] Path traversal attempt detected: '\(filename)' resolves outside sandbox."
            )
        }
        
        // Alt dizinleri oluştur (dosya adı 'subfolder/file.png' gibi olabilir)
        let parentDir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        return fileURL.path
    }
    
    /// Python scriptini geçici dosyaya yazar ve yolunu döner.
    public func writeScript(content: String, filename: String) throws -> String {
        let filePath = try resolvePath(for: filename, in: scriptsURL)
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)
        return filePath
    }
    
    /// Geçici dosyayı temizler.
    public func cleanup(filename: String) {
        do {
            let filePath = try resolvePath(for: filename, in: scriptsURL)
            if FileManager.default.fileExists(atPath: filePath) {
                try FileManager.default.removeItem(atPath: filePath)
            }
        } catch {
            // Cleanup hataları sessizce yutulur — kritik değil
            AgentLogger.logWarn("[BlenderSandbox] Cleanup failed for \(filename): \(error.localizedDescription)")
        }
    }
}
