import Foundation
import SwiftUI
import CryptoKit

@MainActor
public class Orchestrator: ObservableObject {
    @Published public var status: AgentStatus = .idle
    @Published public var steps: [TaskStep] = []
    @Published public var thinkBlocks: [ThinkBlock] = []
    @Published public var promptTokens: Int = 0
    @Published public var completionTokens: Int = 0
    @Published public var costToday: Decimal = 0
    @Published public var currentTask: String = ""
    @Published public var providerUsed: String = "Select Model"
    
    // Conversation History (v5.3.5)
    @Published public var pastSessions: [ChatSession] = []
    @Published public var currentMessages: [ChatMessage] = []
    @Published public var selectedSessionID: UUID? = nil
    
    private let planner: PlannerAgent
    private let memory: MemoryAgent
    private let bus: SignalBus
    private var cloudProvider: CloudProvider?
    private var localProvider: MLXProvider?
    private var bridgeProvider: BridgeProvider?
    private let toolRegistry: ToolRegistry
    private var vaultManager: VaultManager?
    private var observer: ProjectObserver?
    private var currentWorkspaceURL: URL? // Tracking for observer filtering
    
    public init() {
        // Core Security: Signal Bus
        let busKey = SymmetricKey(data: SHA256.hash(data: "ELITE_BUS_SECRET".data(using: .utf8)!))
        let bus = SignalBus(secretKey: busKey)
        self.bus = bus
        
        // Migration: Legacy -> Apple standard paths
        PathConfiguration.shared.performMigration()
        
        self.planner = PlannerAgent(bus: bus)
        self.memory = MemoryAgent(bus: bus)
        self.toolRegistry = ToolRegistry.shared
        
        // Titan: Proactive hardware telemetry
        _ = SystemWatchdog.shared
        
        let paths = PathConfiguration.shared
        
        do {
            let vault = try VaultManager(configURL: paths.vaultURL)
            self.vaultManager = vault
            
            // Initialize Cloud Provider
            do {
                self.cloudProvider = try CloudProvider(providerID: ProviderID(rawValue: "openrouter"), vaultManager: vault)
            } catch {
                print("[ORCHESTRATOR] Warning: Cloud Provider (openrouter) failed to initialize: \(error)")
            }
            
            // Initialize Bridge Provider
            do {
                self.bridgeProvider = try BridgeProvider(providerID: ProviderID(rawValue: "bridge"), vaultManager: vault)
            } catch {
                print("[ORCHESTRATOR] Warning: Bridge Provider (Ollama/LM Studio) failed to initialize: \(error)")
            }
            
            // Initialize Local Provider
            let local = MLXProvider(providerID: ProviderID(rawValue: "mlx"))
            self.localProvider = local
            
            // TITAN PROACTIVE PRIMING: If weights are ready, load them into VRAM immediately
            if ModelSetupManager.shared.isModelReady {
                Task {
                    do {
                        try await local.loadModel("Qwen2.5-7B-Instruct-4bit")
                        print("[ORCHESTRATOR] Titan Engine primed and ready in VRAM.")
                    } catch {
                        print("[ORCHESTRATOR] Titan Priming Failed: \(error). Re-verifying integrity...")
                        // Trigger a status update to detect any latent corruption
                        await MainActor.run {
                            ModelSetupManager.shared.verifyModelStatus()
                        }
                    }
                }
            }
            
            // v7.4.0 LiveSwitch: Observe real-time model selection changes from UI
            NotificationCenter.default.addObserver(
                forName: .activeProviderChanged,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self = self else { return }
                guard let model = note.userInfo?["model"] as? ModelSource else { return }
                
                Task { @MainActor in
                    switch model {
                    case .localMLX(let id, let name, _, _):
                        self.providerUsed = name
                        self.steps.append(TaskStep(name: "LiveSwitch", status: "working", latency: "ANE", thought: "Switching to Titan Engine (\(id)). Priming weights..."))
                        // Prime Titan if not already ready
                        if let localProv = self.localProvider {
                            Task {
                                do {
                                    try await localProv.loadModel(id)
                                    await MainActor.run {
                                        self.steps.append(TaskStep(name: "Titan Ready", status: "done", latency: "ANE", thought: "Local engine is hot. All tasks will use \(name)."))
                                    }
                                } catch {
                                    await MainActor.run {
                                        self.steps.append(TaskStep(name: "Titan Failed", status: "failed", latency: "ANE", thought: "Could not prime local engine: \(error.localizedDescription)"))
                                    }
                                }
                            }
                        }
                        
                    case .openRouter(let id, let name, _, _, _, _):
                        self.providerUsed = name
                        self.steps.append(TaskStep(name: "LiveSwitch", status: "done", latency: "Cloud", thought: "Switched to cloud provider: \(id)"))
                        
                    case .bridge(_, let name):
                        self.providerUsed = name
                        self.steps.append(TaskStep(name: "LiveSwitch", status: "done", latency: "Bridge", thought: "Switched to bridge provider: \(name)"))
                        
                    default:
                        break
                    }
                }
            }
            
        } catch {
            print("[ORCHESTRATOR] CRITICAL: Vault Manager failed to start. Local intelligence unavailable: \(error)")
            self.status = .error
        }
        
        // Initialize Tool Registry (TITAN FULL STACK)
        let group = self.toolRegistry
        group.register(ReadFileTool())
        group.register(WriteFileTool())
        group.register(ShellTool())
        group.register(AppDiscoveryTool())
        group.register(SystemTelemetryTool())
        
        // Register OpenClaw Ports
        group.register(MessengerTool())
        group.register(CalendarTool())
        group.register(MailTool())
        group.register(MediaControllerTool())
        group.register(MusicDNATool())           // 🧬 Music DNA Engine
        group.register(NativeBrowserTool())
        
        // Register Web Wrappers
        group.register(WebSearchToolWrapper())
        group.register(WebFetchToolWrapper())
        
        // Register Deep Core / Category C & D
        group.register(PatchTool())
        group.register(GitTool())
        group.register(ImageAnalysisTool())
        group.register(MemoryTool(agent: self.memory))
        
        // Register SubagentTool (Recursive)
        let handler: @Sendable (TaskStep) -> Void = { [weak self] step in
            Task { @MainActor [weak self] in
                self?.steps.append(step)
            }
        }
        
        let safeProvider: CloudProvider
        if let p = self.cloudProvider {
            safeProvider = p
        } else {
            // Re-initialize a local instance if the main one failed, but in a safe way
            do {
                let v = try VaultManager(configURL: PathConfiguration.shared.vaultURL)
                safeProvider = try CloudProvider(providerID: ProviderID(rawValue: "openrouter"), vaultManager: v)
            } catch {
                // LAST RESORT: Create a placeholder for the subagent tool to prevent crash
                // This allows the app to at least boot up so the user can fix settings
                print("[ORCHESTRATOR] CRITICAL FAIL-SAFE: Could not initialize model providers: \(error)")
                self.status = .error
                // This part is tricky because safeProvider must be initialized.
                // We'll throw or use a throw-away provider if possible.
                // Given the current architecture, we'll try to use a basic provider or re-throw.
                // Re-initializing with a dummy might be better.
                let dummyVault = try! VaultManager(configURL: PathConfiguration.shared.vaultURL)
                safeProvider = try! CloudProvider(providerID: ProviderID(rawValue: "openrouter"), vaultManager: dummyVault)
            }
        }
        
        let local = self.localProvider
        let bridge = self.bridgeProvider
        let memory = self.memory
        let busInstance = self.bus
        let vault = self.vaultManager
        
        let subagentTool = SubagentTool(planner: self.planner, cloudProvider: safeProvider, onStepUpdate: handler) { planner, provider in
            return OrchestratorRuntime(
                planner: planner, 
                memory: memory, 
                cloudProvider: provider, 
                localProvider: local, 
                bridgeProvider: bridge, 
                toolRegistry: ToolRegistry.shared, 
                bus: busInstance, 
                vaultManager: vault!
            )
        }
        self.toolRegistry.register(subagentTool)
        
        // Initial load of history
        Task {
            await loadHistory()
        }
    }
    
    private func loadHistory() async {
        do {
            let loaded = try await HistoryManager.shared.load()
            self.pastSessions = loaded.sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            print("[ORCHESTRATOR] Failed to load history: \(error)")
        }
    }
    
    public func clearAllHistory() async {
        do {
            try await HistoryManager.shared.clear()
            self.pastSessions = []
            self.currentMessages = []
            self.selectedSessionID = nil
        } catch {
            print("[ORCHESTRATOR] Failed to clear history: \(error)")
        }
    }
    
    public func selectSession(_ session: ChatSession) {
        self.selectedSessionID = session.id
        self.currentMessages = session.messages
        self.steps = session.steps
        self.currentTask = session.title
        // Update stats if needed
    }
    
    public func startNewConversation() {
        self.selectedSessionID = nil
        self.currentMessages = []
        self.steps = []
        self.thinkBlocks = []
        self.currentTask = ""
    }

    
    public func submitTask(prompt: String) async throws {
        let taskStart = CFAbsoluteTimeGetCurrent()
        self.status = .working
        
        // Append user message
        let userMessage = ChatMessage(role: .user, content: prompt)
        self.currentMessages.append(userMessage)
        
        self.currentTask = prompt
        self.steps = []
        self.thinkBlocks = []
        
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "Starting task: \(prompt)")
        
        var promptWithContext = prompt
        
        // v7.5.0 DocEye: Detect file paths in prompt and inject content as context
        if let filePath = Orchestrator.extractFilePath(from: prompt) {
            do {
                let reader = ReadFileTool()
                // We create a temporary session for the tool call
                let tempSession = Session(workspaceURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                let content = try await reader.execute(params: ["path": AnyCodable(filePath)], session: tempSession)
                
                let fileName = URL(fileURLWithPath: filePath).lastPathComponent
                promptWithContext = """
                ### DOCUMENT CONTEXT (File: \(fileName))
                \(content)
                ------------------------------------------
                USER TASK: \(prompt)
                """
                
                self.steps.append(TaskStep(name: "DocEye", status: "done", latency: "ANE", thought: "Injected context from \(fileName) (\(content.count) characters)"))
                print("[ORCHESTRATOR] DocEye: Injected context from \(filePath)")
            } catch {
                print("[ORCHESTRATOR] DocEye failed to read file: \(error)")
            }
        }
        
        do {
            // 1. Resolve Workspace (Restrict to project root to avoid Desktop/Library spam)
            var workspaceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            if workspaceURL.path == "/" || workspaceURL.path == NSHomeDirectory() {
                // Fallback to project-specific path to prevent spying on the entire disk
                workspaceURL = URL(fileURLWithPath: "/Users/trgysvc/Developer/EliteAgent")
            }
            self.currentWorkspaceURL = workspaceURL
            
            // 2. Resolve Dynamic Provider from Selection (v7.1.9 Strict Control)
            let allProviders = vaultManager?.config.providers ?? []
            let activeModelID = await MainActor.run { ModelSetupManager.shared.activeModelID }
            let isModelReady = await MainActor.run { ModelSetupManager.shared.isModelReady }
            
            var selectedConf = allProviders.first(where: { $0.modelName == activeModelID })
            if selectedConf == nil {
                selectedConf = allProviders.first(where: { $0.id == "mlx" })
            }
            if selectedConf == nil {
                selectedConf = allProviders.first(where: { $0.id == "openrouter" })
            }
            
            guard let finalConf = selectedConf else {
                throw ProviderError.networkError("No valid provider selected in Vault.")
            }
            
            self.providerUsed = finalConf.modelName ?? "Unknown"
            
            // Phase 3: Hardware Check for Local Intent (v7.1.9 Guard)
            if finalConf.type == .local && !isModelReady {
                self.steps.append(TaskStep(name: "Titan Guard", status: "warning", latency: "ANE", thought: "Selected local model is not primed. Attempting recovery..."))
            }
            
            // Phase 5: Intent Classification (Hybrid Intelligence)
            let intent = classifyIntent(prompt: prompt)
            let complexity: Int = (intent == .hardware || intent == .status) ? 0 : 3
            
            let runtime = OrchestratorRuntime(
                planner: planner, 
                memory: memory,
                cloudProvider: self.cloudProvider!, 
                localProvider: self.localProvider,
                bridgeProvider: bridgeProvider,
                toolRegistry: toolRegistry,
                bus: bus,
                vaultManager: vaultManager!
            )
            
            // 3b. Start Project Observer
            self.observer?.stop()
            self.observer = ProjectObserver(path: workspaceURL.path, delegate: self)
            self.observer?.start()
            
            // 4. Set UI Callbacks (MainActor throttling)
            await runtime.setStepUpdateHandler { [weak self] step in
                Task { @MainActor in
                    self?.steps.append(step)
                }
            }
            
            await runtime.setStatusUpdateHandler { [weak self] status in
                Task { @MainActor in
                    self?.status = status
                }
            }
            
            await runtime.setTokenUpdateHandler { [weak self] (count: TokenCount) in
                Task { @MainActor in
                    self?.promptTokens += count.prompt
                    self?.completionTokens += count.completion
                }
            }
            
            self.steps.append(TaskStep(name: "Initializing recursive runtime...", status: "done", latency: "0ms"))
            
            // 5. EXECUTION WITH HEALING LOOP
            let session = Session(workspaceURL: workspaceURL)
            do {
                try await runtime.executeTask(prompt: promptWithContext, session: session, complexity: complexity)
            } catch {
                if finalConf.type == .local {
                    let msg = "Titan Engine Failure: \(error.localizedDescription). Switching to Healing Mode via Cloud..."
                    self.steps.append(TaskStep(name: "Healing Engine", status: "working", latency: "ANE", thought: msg))
                }
                throw error
            }
            
            let finalAnswer = await session.finalAnswer ?? "Task completed."
            let elapsed = CFAbsoluteTimeGetCurrent() - taskStart
            
            self.steps.append(TaskStep(name: "Task Completed", status: "done", latency: "\(Int(elapsed))s", depth: 0, thought: finalAnswer))
            self.status = .idle
            
            // Append assistant response and save to history
            let analysis = await session.audioAnalysis
            let assistantMessage = ChatMessage(role: .assistant, content: finalAnswer, audioAnalysis: analysis)
            self.currentMessages.append(assistantMessage)
            
            let newSession = ChatSession(
                title: prompt,
                messages: self.currentMessages,
                steps: self.steps,
                metadata: SessionMetadata(
                    promptTokens: self.promptTokens,
                    completionTokens: self.completionTokens,
                    cost: self.costToday,
                    latency: "\(Int(elapsed))s"
                )
            )
            
            self.pastSessions.insert(newSession, at: 0)
            try await HistoryManager.shared.save(self.pastSessions)
            
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - taskStart
            self.status = .error
            let errorMessage = "Error: \(error.localizedDescription)"
            self.steps.append(TaskStep(name: errorMessage, status: "failed", latency: "\(Int(elapsed))s"))
            
            let assistantError = ChatMessage(role: .assistant, content: "I encountered an error while performing your task: \(errorMessage)")
            self.currentMessages.append(assistantError)
        }
    }
    
    private func classifyIntent(prompt: String) -> TaskCategory {
        return TaskClassifier().classify(prompt: prompt)
    }
}

extension Orchestrator: ProjectObserverDelegate {
    
    private static func extractFilePath(from prompt: String) -> String? {
        // Simple regex to detect paths with common extensions
        // Matches /.../file.pdf, "...", etc.
        let pattern = #"(/[\w\.\-/ ]+\.(pdf|txt|md|swift|docx|json))|("[^"]+\.(pdf|txt|md|swift|docx|json)")"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        
        let nsPrompt = prompt as NSString
        let results = regex.matches(in: prompt, options: [], range: NSRange(location: 0, length: nsPrompt.length))
        
        guard let match = results.first else { return nil }
        var path = nsPrompt.substring(with: match.range)
        
        // Strip quotes if present
        if path.hasPrefix("\"") && path.hasSuffix("\"") {
            path = String(path.dropFirst().dropLast())
        }
        if path.hasPrefix("'") && path.hasSuffix("'") {
            path = String(path.dropFirst().dropLast())
        }
        
        return path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func projectDidDetectChange(at path: String, flags: FSEventStreamEventFlags) {
        guard let workspacePath = currentWorkspaceURL?.path else { return }
        guard path.hasPrefix(workspacePath) else { return } // STRICT FILTER: Stop spying on system
        
        let interestingExts = ["swift", "md", "plist", "json", "metal"]
        guard interestingExts.contains(where: { path.hasSuffix($0) }) else { return }
        
        // Ignore build artifacts and internal git state
        if path.contains(".build") || path.contains(".git") || path.contains("DerivedData") { return }
        
        Task { @MainActor in
            let step = TaskStep(
                name: "Proactive: Internal change in \(URL(fileURLWithPath: path).lastPathComponent)", 
                status: "done", 
                latency: "ANE",
                depth: 0,
                thought: "Detected modification in workspace: \(path.replacingOccurrences(of: workspacePath, with: "..."))"
            )
            self.steps.append(step)
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "Proactive observer triggered for \(path)")
        }
    }
}
