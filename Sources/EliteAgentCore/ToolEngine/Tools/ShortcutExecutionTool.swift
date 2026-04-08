import Foundation

public enum ShortcutError: Error, LocalizedError {
    case timeout
    case executionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .timeout: return "Kısayol işlemi 15 saniye içinde yanıt vermedi ve sonlandırıldı."
        case .executionFailed(let msg): return "Kısayol hatası: \(msg)"
        }
    }
}

/// ShortcutExecutionTool, belirli bir macOS Kısayolunu çalıştırır.
/// Girdi (input) parametresi ile işlem bağlamını kısayola aktarabilir.
public struct ShortcutExecutionTool: AgentTool {
    public let name = "run_shortcut"
    public let description = """
    Belirli bir macOS Kısayolunu seçilen parametrelerle çalıştırır. Sadece kullanıcı net bir şekilde kısayol (shortcut) komutu verirse kullan.
    Parametre:
    - name (string - zorunlu)
    - input_text (string - isteğe bağlı)
    """
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws -> String {
        guard let name = params["name"]?.value as? String else {
            throw ToolError.missingParameter("Kısayol adı (name) gereklidir.")
        }
        
        let inputText = params["input_text"]?.value as? String ?? ""
        
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = ["run", name]
                
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                if !inputText.isEmpty {
                    let inputPipe = Pipe()
                    process.standardInput = inputPipe
                    
                    // stdin üzerinden input gönderme
                    if let data = inputText.data(using: .utf8) {
                        try? inputPipe.fileHandleForWriting.write(contentsOf: data)
                        inputPipe.fileHandleForWriting.closeFile()
                    }
                }
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8) ?? ""
                        return "[SUCCESS] '\(name)' kısayolu çalıştırıldı. Çıktı: \(output)"
                    } else {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMsg = String(data: errorData, encoding: .utf8) ?? "Bilinmeyen Hata"
                        throw ShortcutError.executionFailed(errorMsg)
                    }
                } catch {
                    throw ShortcutError.executionFailed(error.localizedDescription)
                }
            }
            
            // 15s Timeout
            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000)
                throw ShortcutError.timeout
            }
            
            guard let firstResult = try await group.next() else {
                throw ShortcutError.executionFailed("İşlem başlatılamadı.")
            }
            
            group.cancelAll()
            return firstResult
        }
    }
}
