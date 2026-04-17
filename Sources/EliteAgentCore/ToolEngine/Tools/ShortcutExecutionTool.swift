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
    public let summary = "Execute native macOS Shortcuts."
    public let description = """
    Belirli bir macOS Kısayolunu seçilen parametrelerle çalıştırır. Sadece kullanıcı net bir şekilde kısayol (shortcut) komutu verirse kullan.
    Parametre:
    - name (string - zorunlu)
    - input_text (string - isteğe bağlı)
    """
    public let ubid: Int128 = 49 // Token 'R' in Qwen 2.5
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        guard let name = params["name"]?.value as? String else {
            throw AgentToolError.missingParameter("Kısayol adı (name) gereklidir.")
        }
        
        let inputText = params["input_text"]?.value as? String ?? ""
        
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
            if let data = inputText.data(using: .utf8) {
                try? inputPipe.fileHandleForWriting.write(contentsOf: data)
                try? inputPipe.fileHandleForWriting.close()
            }
        }
        
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in
                    continuation.resume()
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            if process.terminationStatus == 0 {
                let data = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
                let output = String(data: data, encoding: .utf8) ?? ""
                return "[SUCCESS] '\(name)' kısayolu çalıştırıldı. Çıktı: \(output)"
            } else {
                let errorData = try errorPipe.fileHandleForReading.readToEnd() ?? Data()
                let errorMsg = String(data: errorData, encoding: .utf8) ?? "Bilinmeyen Hata"
                throw AgentToolError.executionError(errorMsg)
            }
        } catch {
            throw AgentToolError.executionError(error.localizedDescription)
        }
    }
}
