import Foundation
import SwiftUI
import CryptoKit

public struct PendingTask: Sendable {
    public let prompt: String
    public let forceProviders: [ProviderID]?
    public let promptWithContext: String
    public let complexity: Int
}

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
    @Published public var config: InferenceConfig = .default
    
    // v7.8.0 Centralized State
    public var sessionState = AISessionState.shared
    
    // Fallback Approval State
    @Published public var pendingTask: PendingTask? = nil
    
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
    private var currentWorkspaceURL: URL? 
    
    public init() {
        let busKey = SymmetricKey(data: SHA256.hash(data: "ELITE_BUS_SECRET".data(using: .utf8)!))
        let bus = SignalBus(secretKey: busKey)
        self.bus = bus
        
        PathConfiguration.shared.performMigration()
        
        self.planner = PlannerAgent(bus: bus)
        self.memory = MemoryAgent(bus: bus)
        self.toolRegistry = ToolRegistry.shared
        
        _ = SystemWatchdog.shared
        
        let paths = PathConfiguration.shared
        
        do {
            let vault = try VaultManager(configURL: paths.vaultURL)
            self.vaultManager = vault
            
            Task {
                let savedConfig = await ConfigManager.shared.get()
                self.config = savedConfig
            }
            
            do {
                self.cloudProvider = try CloudProvider(providerID: .openrouter, vaultManager: vault)
            } catch {
                print("Failed to init cloud provider: \(error)")
            }
            
            do {
                self.bridgeProvider = try BridgeProvider(providerID: .bridge, vaultManager: vault)
            } catch {
                print("Failed to init bridge provider: \(error)")
            }
            
            let local = MLXProvider(providerID: .mlx)
            self.localProvider = local
            
            if ModelSetupManager.shared.isModelReady {
                Task {
                    do {
                        try await local.loadModel("Qwen2.5-7B-Instruct-4bit")
                    } catch {
                        print("[ORCHESTRATOR] Titan Priming Failed: \(error)")
                    }
                }
            }
            
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
                        if let localProv = self.localProvider {
                            Task { try? await localProv.loadModel(id) }
                        }
                    case .openRouter(_, let name, _, _, _, _):
                        self.providerUsed = name
                    case .bridge(_, let name):
                        self.providerUsed = name
                    default:
                        break
                    }
                }
            }
            
        } catch {
            self.status = .error
        }
        
        let group = self.toolRegistry
        group.register(ReadFileTool())
        group.register(WriteFileTool())
        group.register(ShellTool())
        group.register(AppDiscoveryTool())
        group.register(SystemTelemetryTool())
        group.register(MessengerTool())
        group.register(CalendarTool())
        group.register(MailTool())
        group.register(MediaControllerTool())
        group.register(MusicDNATool())
        group.register(NativeBrowserTool())
        group.register(WebSearchToolWrapper())
        group.register(WebFetchToolWrapper())
        group.register(PatchTool())
        group.register(GitTool())
        group.register(ImageAnalysisTool())
        group.register(MemoryTool(agent: self.memory))
        
        let handler: @Sendable (TaskStep) -> Void = { [weak self] step in
            Task { @MainActor [weak self] in
                self?.steps.append(step)
            }
        }
        
        let safeProvider: CloudProvider
        if let p = self.cloudProvider {
            safeProvider = p
        } else {
            let dummyVault = try! VaultManager(configURL: PathConfiguration.shared.vaultURL)
            safeProvider = try! CloudProvider(providerID: .openrouter, vaultManager: dummyVault)
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
        
        Task { await loadHistory() }
    }
    
    private func loadHistory() async {
        do {
            let loaded = try await HistoryManager.shared.load()
            self.pastSessions = loaded.sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            print("[ORCHESTRATOR] Failed to load history: \(error)")
        }
    }
    
    public func selectSession(_ session: ChatSession) {
        self.selectedSessionID = session.id
        self.currentMessages = session.messages
        self.steps = session.steps
        self.currentTask = session.title
    }
    
    public func startNewConversation() {
        self.selectedSessionID = nil
        self.currentMessages = []
        self.steps = []
        self.thinkBlocks = []
        self.currentTask = ""
    }
    
    public func clearAllHistory() async {
        do {
            try await HistoryManager.shared.clear()
            self.pastSessions = []
            self.currentMessages = []
            self.steps = []
            self.selectedSessionID = nil
            self.currentTask = ""
        } catch {
            print("[ORCHESTRATOR] Failed to clear history: \(error)")
        }
    }

    public func approveFallback(decision: FallbackDecision) {
        guard let pending = self.pendingTask else { return }
        let prompt = pending.prompt
        self.pendingTask = nil
        
        // Immediate UI reset: Clear the modal and unlock input
        sessionState.resetForNewTask()
        
        Task {
            switch decision {
            case .useCloud:
                try? await submitTask(prompt: prompt, forceProviders: [.openrouter], promptOnFallback: false)
            case .useOllama:
                try? await submitTask(prompt: prompt, forceProviders: [.bridge], promptOnFallback: false)
            case .cancel:
                self.status = .idle
                self.steps.append(TaskStep(name: "Görev İptal Edildi", status: "failed", latency: "ANE", thought: "Kullanıcı bulut model geçişini reddetti."))
            }
        }
    }
    
    public func cancelTask() {
        self.status = .idle
        self.pendingTask = nil
    }

    public func submitTask(prompt: String, forceProviders: [ProviderID]? = nil, strictLocal: Bool? = nil, promptOnFallback: Bool? = nil) async throws {
        let taskStart = CFAbsoluteTimeGetCurrent()
        self.status = .working
        
        self.config = await ConfigManager.shared.get()
        var effectiveConfig = self.config
        
        let policy = sessionState.fallbackPolicy
        effectiveConfig.fallbackPolicy = policy
        
        if let sl = strictLocal { effectiveConfig.strictLocal = sl }
        
        // 1. Reset for new task
        sessionState.resetForNewTask()
        sessionState.selectedModel = effectiveConfig.providerPriority.first?.rawValue ?? "mlx"
        
        // Precedence logic: If forceProviders is set (e.g. from fallback buttons), it overrides priority
        if pendingTask == nil {
            let userMessage = ChatMessage(role: .user, content: prompt)
            self.currentMessages.append(userMessage)
            self.currentTask = prompt
            self.steps = []
            self.thinkBlocks = []
        }
        
        AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "Starting task: \(prompt)")
        
        var promptWithContext = prompt
        if let filePath = Orchestrator.extractFilePath(from: prompt) {
            do {
                let reader = ReadFileTool()
                let tempSession = Session(workspaceURL: URL(fileURLWithPath: "/Users/trgysvc/Developer/EliteAgent"))
                let content = try await reader.execute(params: ["path": AnyCodable(filePath)], session: tempSession)
                let fileName = URL(fileURLWithPath: filePath).lastPathComponent
                promptWithContext = "### DOCUMENT CONTEXT (File: \(fileName))\n\(content)\n------------------------------------------\nUSER TASK: \(prompt)"
                self.steps.append(TaskStep(name: "DocEye", status: "done", latency: "ANE", thought: "Injected context from \(fileName)"))
            } catch {
                print("[ORCHESTRATOR] DocEye failed: \(error)")
            }
        }
        
        do {
            let workspaceURL = URL(fileURLWithPath: "/Users/trgysvc/Developer/EliteAgent")
            self.currentWorkspaceURL = workspaceURL
            
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
            
            self.observer?.stop()
            self.observer = ProjectObserver(path: workspaceURL.path, delegate: self)
            self.observer?.start()
            
            await runtime.setStepUpdateHandler { [weak self] step in
                Task { @MainActor in self?.steps.append(step) }
            }
            
            await runtime.setStatusUpdateHandler { [weak self] status in
                Task { @MainActor in self?.status = status }
            }
            
            await runtime.setTokenUpdateHandler { [weak self] count in
                Task { @MainActor in
                    self?.promptTokens += count.prompt
                    self?.completionTokens += count.completion
                }
            }
            
            let session = Session(workspaceURL: workspaceURL)
            let intent = classifyIntent(prompt: prompt)
            let complexity: Int = (intent == .codeGeneration || intent == .research) ? 4 : 3
            
            try await runtime.executeTask(
                prompt: promptWithContext, 
                session: session, 
                complexity: complexity, 
                forceProviders: forceProviders,
                config: effectiveConfig
            )
            
            let finalAnswer = await session.finalAnswer ?? "Task completed."
            let elapsed = CFAbsoluteTimeGetCurrent() - taskStart
            
            self.steps.append(TaskStep(name: "Task Completed", status: "done", latency: "\(Int(elapsed))s", depth: 0, thought: finalAnswer))
            self.status = .idle
            
            let assistantMessage = ChatMessage(role: .assistant, content: finalAnswer)
            self.currentMessages.append(assistantMessage)
            
            let newSession = ChatSession(
                title: prompt,
                messages: self.currentMessages,
                steps: self.steps,
                metadata: SessionMetadata(promptTokens: self.promptTokens, completionTokens: self.completionTokens, cost: 0, latency: "\(Int(elapsed))s")
            )
            self.pastSessions.insert(newSession, at: 0)
            try await HistoryManager.shared.save(self.pastSessions)
            
        } catch let error as InferenceError {
            if case .localProviderUnavailable(let reason) = error {
                sessionState.fallbackReason = reason
                sessionState.activeProvider = "local_failed"
                
                if effectiveConfig.fallbackPolicy == .promptBeforeSwitch && (promptOnFallback ?? true) {
                    sessionState.requiresUserAcknowledgement = true
                    sessionState.isInputLocked = true
                    self.pendingTask = PendingTask(prompt: prompt, forceProviders: forceProviders, promptWithContext: promptWithContext, complexity: 3)
                    self.status = .awaitingFallbackApproval(taskID: UUID().uuidString, error: reason)
                    self.steps.append(TaskStep(name: "Titan Hazır Değil", status: "warning", latency: "ANE", thought: reason))
                } else if effectiveConfig.fallbackPolicy == .strictLocal {
                    sessionState.isInputLocked = false
                    self.status = .error
                    self.steps.append(TaskStep(name: "Strict Local Error", status: "failed", latency: "0s", thought: "Cloud fallback disabled by policy."))
                } else {
                    sessionState.isInputLocked = false
                }
            } else {
                sessionState.isInputLocked = false
                self.status = .error
                self.steps.append(TaskStep(name: "Inference Error", status: "failed", latency: "0s", thought: "\(error)"))
            }
            throw error
        } catch {
            sessionState.isInputLocked = false
            self.status = .error
            self.steps.append(TaskStep(name: "System Error", status: "failed", latency: "0s", thought: error.localizedDescription))
            throw error
        }
    }
    
    private func classifyIntent(prompt: String) -> TaskCategory {
        return TaskClassifier().classify(prompt: prompt)
    }
}

extension Orchestrator: ProjectObserverDelegate {
    private static func extractFilePath(from prompt: String) -> String? {
        let pattern = #"(/[\w\.\-/ ]+\.(pdf|txt|md|swift|docx|json))|("[^"]+\.(pdf|txt|md|swift|docx|json)")"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsPrompt = prompt as NSString
        let results = regex.matches(in: prompt, options: [], range: NSRange(location: 0, length: nsPrompt.length))
        guard let match = results.first else { return nil }
        var path = nsPrompt.substring(with: match.range)
        if path.hasPrefix("\"") && path.hasSuffix("\"") { path = String(path.dropFirst().dropLast()) }
        return path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func projectDidDetectChange(at path: String, flags: FSEventStreamEventFlags) {
        guard let workspacePath = currentWorkspaceURL?.path, path.hasPrefix(workspacePath) else { return }
        if path.contains(".build") || path.contains(".git") || path.contains("DerivedData") { return }
        Task { @MainActor in
            self.steps.append(TaskStep(name: "Proactive Change: \(URL(fileURLWithPath: path).lastPathComponent)", status: "done", latency: "ANE", thought: "Workspace modification detected."))
        }
    }
}
