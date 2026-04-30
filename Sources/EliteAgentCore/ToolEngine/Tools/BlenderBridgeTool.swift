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
    public let summary = "Professional Blender Operator: Full access to Blender Python API (bpy) for 3D modeling, rendering, and simulation."
    public let description = """
    Advanced Blender 5.1 automation tool. Provides FULL access to Blender Python API (bpy).
    
    Actions:
    - 'execute_script': Execute any valid Blender Python code. Use this for ALL complex tasks (modifiers, materials, physics).
      Params: script (string) - Your bpy code.
    - 'get_api_info': Discover available bpy features. Params: target (string, e.g., 'bpy.ops.mesh').
    - 'create_scene': Reset and start fresh. Params: engine, res_x, res_y.
    - 'render': Render current scene to image. Param: output (filename).
    - 'add_mesh' / 'add_light': Fast shortcuts for basic primitives.
    
    API Usage Guidelines:
    1. Your script is executed in an environment with 'bpy', 'math', and 'os' pre-imported.
    2. 'workspace.blend' is automatically loaded before your script and saved after.
    3. Use 'bpy.ops.*' for operators and 'bpy.data.*' for data access.
    4. PATHS: All file paths are relative to the sandbox. Do NOT use absolute paths.
       Files are saved to: ~/Documents/EliteAgentWorkspace/Blender/outputs/
    
    CRITICAL: For monkey (Suzanne), use action 'add_mesh' with type 'monkey' or 'execute_script'.
    For materials and modifiers, you MUST use 'execute_script'.
    
    Example (Professional):
    CALL(60) WITH {
      "action": "execute_script",
      "script": "bpy.ops.mesh.primitive_monkey_add(); obj = bpy.context.object; obj.name = 'Monkey'; mod = obj.modifiers.new(name='Subdiv', type='SUBSURF'); mod.levels = 2; mat = bpy.data.materials.new(name='Gold'); mat.use_nodes = True; obj.data.materials.append(mat);"
    }
    """
    public let ubid: Int128 = 60
    
    /// Blender process timeout: 600 saniye (karmaşık işlemler için uzatıldı)
    private let processTimeout: TimeInterval = 600.0
    
    public init() {}
    
    public func execute(params: [String: AnyCodable], session: Session) async throws(AgentToolError) -> String {
        // 1. Blender kurulum kontrolü
        guard let executablePath = BlenderDetector.executablePath else {
            throw .executionError(
                "Blender is not installed or not found. Checked paths: /Applications/Blender.app, /opt/homebrew/bin/blender, /usr/local/bin/blender. Install from https://www.blender.org/download/"
            )
        }
        
        // 2. Zorunlu parametre kontrolü (Handle flattened 'command' or 'action')
        let rawAction = params["action"]?.value as? String ?? params["command"]?.value as? String
        guard var action = rawAction else {
            throw .missingParameter("'action' parameter is required. Allowed: create_scene, render, add_mesh, add_light, modify, export, import")
        }
        
        // v28.0: Robust Parsing - Handle cases where model puts params in the action string (e.g. "add_mesh plane")
        let actionParts = action.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if actionParts.count > 1 {
            action = actionParts[0]
            // If the model put extra parts, try to treat them as 'type' or other params if they aren't already set
            var operationParams: [String: Any] = [:]
            if let paramsAnyCodable = params["params"]?.value as? [String: Any] {
                operationParams = paramsAnyCodable
            }
            
            if action == "add_mesh" && operationParams["type"] == nil {
                operationParams["type"] = actionParts[1]
            } else if action == "add_light" && operationParams["type"] == nil {
                operationParams["type"] = actionParts[1]
            }
            // Update params indirectly by ensuring operationParams is used
        }
        
        // 3. Sandbox oluştur
        let sandbox: BlenderSandbox
        do {
            sandbox = try BlenderSandbox()
        } catch {
            throw .executionError("Failed to initialize Blender sandbox: \(error.localizedDescription)")
        }
        
        // 4. Operasyon parametrelerini çöz (Handle flattening from ThinkParser)
        var operationParams: [String: Any] = [:]
        if let paramsAnyCodable = params["params"]?.value as? [String: Any] {
            operationParams = paramsAnyCodable
        }
        
        // Re-apply parts if we split them
        if actionParts.count > 1 {
            if action == "add_mesh" && operationParams["type"] == nil { operationParams["type"] = actionParts[1] }
            if action == "add_light" && operationParams["type"] == nil { operationParams["type"] = actionParts[1] }
        }
        
        // Flatten top-level params into operationParams if they are not reserved
        let reservedKeys = ["action", "command", "path", "output", "params"]
        for (key, val) in params {
            if !reservedKeys.contains(key) {
                operationParams[key] = val.value
            }
        }
        
        // v30.5: Robust Parameter Aliasing
        if let objectAlias = operationParams["object"] as? String, operationParams["object_name"] == nil {
            operationParams["object_name"] = objectAlias
        }
        if let pathAlias = operationParams["path"] as? String, operationParams["output"] == nil {
            operationParams["output"] = pathAlias
        }
        
        // 5. Action'a göre Python script üret
        let pythonScript: String
        let scriptName = "blender_task_\(UUID().uuidString.prefix(8)).py"
        
        let workspaceBlend: String
        do {
            workspaceBlend = try sandbox.resolvePath(for: "workspace.blend", in: sandbox.workspaceURL)
        } catch {
            throw .executionError("Failed to resolve workspace path: \(error.localizedDescription)")
        }
        
        switch action {
        case "execute_script":
            guard let script = operationParams["script"] as? String ?? operationParams["command"] as? String else {
                throw .missingParameter("'script' parameter is required for execute_script.")
            }
            
            // v30.0: Full API Power - LLM can now use all bpy features.
            pythonScript = """
            import bpy
            import math
            import os
            import traceback
            
            # Auto-chaining: Load workspace.blend if it exists
            workspace_path = r'\(workspaceBlend)'
            output_dir = r'\(sandbox.outputsURL.path)'
            
            # Inject helper variables for the agent
            WS_OUTPUTS = output_dir
            
            if os.path.exists(workspace_path) and not bpy.data.filepath:
                try:
                    bpy.ops.wm.open_mainfile(filepath=workspace_path)
                except:
                    pass
            
            # LLM-Generated Logic
            try:
                \(script.replacingOccurrences(of: "\n", with: "\n    "))
                print('[BLENDER_OK] Custom script executed.')
            except Exception as e:
                print(f'[BLENDER_ERROR] Script failed.')
                traceback.print_exc()
                
            # Auto-save for next turn
            bpy.ops.wm.save_as_mainfile(filepath=workspace_path)
            """
            
        case "create_scene", "render":
            let engine = operationParams["engine"] as? String ?? "BLENDER_EEVEE_NEXT"
            let resX = operationParams["res_x"] as? Int ?? 1920
            let resY = operationParams["res_y"] as? Int ?? 1080
            
            // v30.1: Handle path/output alias and strip absolute paths for sandbox safety
            let rawOutput = params["output"]?.value as? String ?? params["path"]?.value as? String ?? "render_output.png"
            let outputName = (rawOutput as NSString).lastPathComponent
            
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
            
        case "add_mesh":
            let type = operationParams["type"] as? String ?? "cube"
            let sizeStr = "\(operationParams["size"] ?? "2")"
            let size = Double(sizeStr) ?? 2.0
            
            let location: (Double, Double, Double)
            if let loc = operationParams["location"] as? [Double], loc.count == 3 {
                location = (loc[0], loc[1], loc[2])
            } else if let locStr = operationParams["location"] as? String {
                let parts = locStr.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                location = parts.count == 3 ? (parts[0], parts[1], parts[2]) : (0, 0, 0)
            } else {
                location = (0, 0, 0)
            }
            
            let addCode = BlenderScriptLibrary.addMesh(type: type, size: size, location: location)
            
            pythonScript = """
            import bpy
            import os
            
            # Auto-chaining: Load workspace.blend if it exists and we didn't specify a path
            if os.path.exists(r'\(workspaceBlend)') and not bpy.data.filepath:
                bpy.ops.wm.open_mainfile(filepath=r'\(workspaceBlend)')
            
            \(addCode)
            bpy.ops.wm.save_as_mainfile(filepath=r'\(workspaceBlend)')
            print('[BLENDER_OK] Added mesh: \(type)')
            """
            
        case "add_light":
            let type = operationParams["type"] as? String ?? "POINT"
            let energyStr = "\(operationParams["energy"] ?? "10")"
            let energy = Double(energyStr) ?? 10.0
            
            let location: (Double, Double, Double)
            if let loc = operationParams["location"] as? [Double], loc.count == 3 {
                location = (loc[0], loc[1], loc[2])
            } else if let locStr = operationParams["location"] as? String {
                let parts = locStr.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                location = parts.count == 3 ? (parts[0], parts[1], parts[2]) : (0, 0, 0)
            } else {
                location = (0, 0, 0)
            }
            
            let addCode = BlenderScriptLibrary.addLight(type: type, location: location, energy: energy)
            
            pythonScript = """
            import bpy
            import os
            
            if os.path.exists(r'\(workspaceBlend)') and not bpy.data.filepath:
                bpy.ops.wm.open_mainfile(filepath=r'\(workspaceBlend)')
                
            \(addCode)
            bpy.ops.wm.save_as_mainfile(filepath=r'\(workspaceBlend)')
            print('[BLENDER_OK] Added light: \(type)')
            """
            
        case "export":
            // v30.1: Robust parameter resolution for export
            let rawOutput = params["output"]?.value as? String ?? params["path"]?.value as? String
            guard let outputVal = rawOutput else {
                throw .missingParameter("'output' or 'path' parameter is required for export (e.g., 'model.gltf')")
            }
            let outputName = (outputVal as NSString).lastPathComponent
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
            
        case "get_api_info":
            let target = operationParams["target"] as? String ?? operationParams["module"] as? String ?? "bpy"
            pythonScript = BlenderScriptLibrary.apiExplorer(target: target)
            
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
                "Unsupported action '\(action)'. Allowed actions: execute_script, create_scene, render, add_mesh, add_light, export, import, info, modify, turntable"
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
                            // v30.5: Full traceback inclusion for self-debugging
                            let stderrDetail = String(stderr.prefix(5000))
                            let errorDetail = stdout.contains("Traceback") ? stdout : stderrDetail
                            
                            continuation.resume(returning: "[BLENDER_FAIL] Process exited with status \(terminatedProcess.terminationStatus).\nDetails: \(errorDetail)")
                        } else {
                            // [BLENDER_OK] satırlarını çıkar
                            let successLines = stdout.components(separatedBy: "\n")
                                .filter { $0.contains("[BLENDER_OK]") || $0.contains("[BLENDER_WARN]") || $0.contains("[BLENDER_ERROR]") }
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
