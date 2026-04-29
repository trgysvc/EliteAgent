import Foundation

/// BlenderBridgeTool: Blender 5.1 headless otomasyon aracı.
///
/// EliteAgent'ın Blender'ı arka planda (GUI'siz) çalıştırarak 3D sahne oluşturma,
/// render, format dönüştürme ve düzenleme yapmasını sağlar.
/// Apple Metal GPU hızlandırma yerel olarak desteklenir (M-serisi).
///
/// Güvenlik Modeli:
/// - Tüm çıktılar BlenderSandbox ile ~/Documents/EliteAgentWorkspace/Blender/ altına izole edilir.
/// - Serbest Python kodu çalıştırma (action: "script") güvenlik nedeniyle devre dışıdır.
/// - Yalnızca BlenderScriptLibrary'deki parametrik şablonlar kullanılır.
/// - CLI üzerinden --cycles-device kullanılmaz, GPU ataması Python API (bpy) ile yapılır.
public struct BlenderBridgeTool: AgentTool, Sendable {
    public let name = "blender_3d"
    public let summary = "Blender 3D: Create scenes, render images, export/import models, turntable animation."
    public let description = """
    Blender 5.1 headless otomasyon aracı. 3D sahne oluşturma, render, format dönüştürme ve düzenleme.
    Apple Metal GPU hızlandırma yerel olarak desteklenir (M-Serisi).
    
    Param: action (string) - 'create_scene', 'render', 'export', 'import', 'info', 'modify', 'turntable'
    Param: path (string, optional) - Kaynak .blend dosya yolu (export/render/info için)
    Param: output (string, optional) - Çıktı dosya adı (örnek: result.png veya model.gltf)
    Param: params (dict, optional) - İşleme özel parametreler (engine, res_x, res_y, objects, object_name, format)
    """
    public let ubid: Int128 = 60
    
    /// Blender process timeout: 300 saniye (uzun renderlar için)
    private let processTimeout: TimeInterval = 300.0
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        // 1. Blender kurulum kontrolü
        guard let executablePath = BlenderDetector.executablePath else {
            throw .executionError(
                "Blender is not installed or not found. Checked paths: /Applications/Blender.app, /opt/homebrew/bin/blender, /usr/local/bin/blender. Install from https://www.blender.org/download/"
            )
        }
        
        // 2. Zorunlu parametre kontrolü
        guard let action = params["action"]?.value as? String else {
            throw .missingParameter("'action' parameter is required. Allowed: create_scene, render, export, import, info, modify, turntable")
        }
        
        // 3. Sandbox oluştur
        let sandbox: BlenderSandbox
        do {
            sandbox = try BlenderSandbox()
        } catch {
            throw .executionError("Failed to initialize Blender sandbox: \(error.localizedDescription)")
        }
        
        // 4. Operasyon parametrelerini çöz
        let operationParams: [String: Any]
        if let paramsAnyCodable = params["params"]?.value as? [String: Any] {
            operationParams = paramsAnyCodable
        } else {
            operationParams = [:]
        }
        
        // 5. Action'a göre Python script üret
        let pythonScript: String
        let scriptName = "blender_task_\(UUID().uuidString.prefix(8)).py"
        
        switch action {
        case "create_scene", "render":
            let engine = operationParams["engine"] as? String ?? "BLENDER_EEVEE_NEXT"
            let resX = operationParams["res_x"] as? Int ?? 1920
            let resY = operationParams["res_y"] as? Int ?? 1080
            let outputName = params["output"]?.value as? String ?? "render_output.png"
            
            let outputPath: String
            do {
                outputPath = try sandbox.resolvePath(for: outputName)
            } catch {
                throw .executionError(error.localizedDescription)
            }
            
            let objects = operationParams["objects"] as? [String] ?? []
            pythonScript = BlenderScriptLibrary.createScene(
                engine: engine,
                resX: resX,
                resY: resY,
                outputPath: outputPath,
                objectBlocks: objects
            )
            
        case "export":
            guard let outputName = params["output"]?.value as? String else {
                throw .missingParameter("'output' parameter is required for export (e.g., 'model.gltf')")
            }
            let outputPath: String
            do {
                outputPath = try sandbox.resolvePath(for: outputName)
            } catch {
                throw .executionError(error.localizedDescription)
            }
            let ext = (outputName as NSString).pathExtension.lowercased()
            guard ["obj", "fbx", "gltf", "glb", "stl"].contains(ext) else {
                throw .invalidParameter("Unsupported export format: '.\(ext)'. Supported: .obj, .fbx, .gltf, .glb, .stl")
            }
            pythonScript = BlenderScriptLibrary.exportModel(exportFormat: ext, outputPath: outputPath)
            
        case "import":
            guard let importFile = params["path"]?.value as? String else {
                throw .missingParameter("'path' parameter is required for import (e.g., '/path/to/model.obj')")
            }
            let ext = (importFile as NSString).pathExtension.lowercased()
            guard ["obj", "fbx", "gltf", "glb"].contains(ext) else {
                throw .invalidParameter("Unsupported import format: '.\(ext)'. Supported: .obj, .fbx, .gltf, .glb")
            }
            pythonScript = BlenderScriptLibrary.importModel(importPath: importFile, importFormat: ext)
            
        case "info":
            pythonScript = BlenderScriptLibrary.sceneInfo()
            
        case "modify":
            guard let objectName = operationParams["object_name"] as? String else {
                throw .missingParameter("'params.object_name' is required for modify action.")
            }
            var location: (Double, Double, Double)? = nil
            var rotation: (Double, Double, Double)? = nil
            var scale: (Double, Double, Double)? = nil
            
            if let loc = operationParams["location"] as? [Double], loc.count == 3 {
                location = (loc[0], loc[1], loc[2])
            }
            if let rot = operationParams["rotation"] as? [Double], rot.count == 3 {
                rotation = (rot[0], rot[1], rot[2])
            }
            if let sc = operationParams["scale"] as? [Double], sc.count == 3 {
                scale = (sc[0], sc[1], sc[2])
            }
            
            pythonScript = BlenderScriptLibrary.modifyObject(
                objectName: objectName,
                location: location,
                rotation: rotation,
                scale: scale
            )
            
        case "turntable":
            let frameCount = operationParams["frames"] as? Int ?? 120
            let engine = operationParams["engine"] as? String ?? "BLENDER_EEVEE_NEXT"
            let outputName = params["output"]?.value as? String ?? "turntable_"
            
            let outputPath: String
            do {
                outputPath = try sandbox.resolvePath(for: outputName)
            } catch {
                throw .executionError(error.localizedDescription)
            }
            
            pythonScript = BlenderScriptLibrary.turntableAnimation(
                frameCount: frameCount,
                outputPath: outputPath,
                engine: engine
            )
            
        default:
            throw .invalidParameter(
                "Unsupported action '\(action)'. Allowed actions: create_scene, render, export, import, info, modify, turntable"
            )
        }
        
        // 6. Script'i sandbox'a yaz
        let scriptPath: String
        do {
            scriptPath = try sandbox.writeScript(content: pythonScript, filename: scriptName)
        } catch {
            throw .executionError("Failed to write Blender script: \(error.localizedDescription)")
        }
        defer { sandbox.cleanup(filename: scriptName) }
        
        // 7. Blender process argümanlarını oluştur
        var arguments = ["--background"]
        
        // Kaynak .blend dosyası varsa (export, info, modify için)
        if let blendPath = params["path"]?.value as? String,
           action != "import" { // import için 'path' kaynak model dosyasıdır, blend değil
            if FileManager.default.fileExists(atPath: blendPath) {
                arguments.append(blendPath)
            }
        }
        
        arguments.append(contentsOf: ["--python", scriptPath])
        
        // 8. Process'i çalıştır
        AgentLogger.logAudit(level: .info, agent: "BlenderBridge", message: "🎨 Executing Blender [\(action)] | Engine: \(operationParams["engine"] as? String ?? "EEVEE")")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            let result: String = try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { terminatedProcess in
                    do {
                        let outputData = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
                        let errorData = try errorPipe.fileHandleForReading.readToEnd() ?? Data()
                        
                        let stdout = String(data: outputData, encoding: .utf8) ?? ""
                        let stderr = String(data: errorData, encoding: .utf8) ?? ""
                        
                        if terminatedProcess.terminationStatus != 0 {
                            // Blender hata çıktısından [BLENDER_ERROR] satırlarını çıkar
                            let blenderErrors = stdout.components(separatedBy: "\n")
                                .filter { $0.contains("[BLENDER_ERROR]") }
                                .joined(separator: "\n")
                            
                            let errorDetail = blenderErrors.isEmpty ? String(stderr.prefix(500)) : blenderErrors
                            continuation.resume(returning: "[BLENDER_FAIL] Process exited with status \(terminatedProcess.terminationStatus).\nDetails: \(errorDetail)")
                        } else {
                            // [BLENDER_OK] satırlarını çıkar
                            let successLines = stdout.components(separatedBy: "\n")
                                .filter { $0.contains("[BLENDER_OK]") || $0.contains("[BLENDER_WARN]") }
                                .joined(separator: "\n")
                            
                            let report = successLines.isEmpty ? "(Blender completed, no status output)" : successLines
                            continuation.resume(returning: report)
                        }
                    } catch {
                        continuation.resume(returning: "[BLENDER_FAIL] Could not read process output: \(error.localizedDescription)")
                    }
                }
                
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            AgentLogger.logAudit(level: .info, agent: "BlenderBridge", message: "🎨 Blender [\(action)] completed. Result: \(result.prefix(200))")
            return result
            
        } catch let error as AgentToolError {
            throw error
        } catch {
            throw .executionError("Blender process execution failed: \(error.localizedDescription)")
        }
    }
}
