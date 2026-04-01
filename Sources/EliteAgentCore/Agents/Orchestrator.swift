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
    private let toolRegistry: ToolRegistry
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
            self.cloudProvider = try CloudProvider(providerID: ProviderID(rawValue: "openrouter"), vaultManager: vault)
            self.localProvider = MLXProvider(providerID: ProviderID(rawValue: "mlx"))
        } catch {
            print("[ORCHESTRATOR] CRITICAL: Failed to initialize Core Services: \(error)")
            self.status = .error
            self.cloudProvider = nil
            self.localProvider = nil
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
            let v = try! VaultManager(configURL: PathConfiguration.shared.vaultURL)
            safeProvider = try! CloudProvider(providerID: ProviderID(rawValue: "openrouter"), vaultManager: v)
        }
        
        let local = self.localProvider
        let subagentTool = SubagentTool(planner: self.planner, cloudProvider: safeProvider, onStepUpdate: handler) { [weak self] planner, provider in
            guard let self = self else { fatalError() }
            return OrchestratorRuntime(planner: planner, memory: self.memory, cloudProvider: provider, localProvider: local, toolRegistry: ToolRegistry.shared, bus: self.bus)
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
        
        do {
            // 1. Resolve Workspace (Restrict to project root to avoid Desktop/Library spam)
            var workspaceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            if workspaceURL.path == "/" || workspaceURL.path == NSHomeDirectory() {
                // Fallback to project-specific path to prevent spying on the entire disk
                workspaceURL = URL(fileURLWithPath: "/Users/trgysvc/Developer/EliteAgent")
            }
            self.currentWorkspaceURL = workspaceURL
            
            // 2. Initialize Runtime
            guard let provider = self.cloudProvider else {
                throw ProviderError.networkError("Cloud Provider not initialized. Please check your vault.plist and API keys.")
            }
            
            self.providerUsed = provider.modelName
            
            // Phase 5: Intent Classification (Hybrid Intelligence)
            let intent = classifyIntent(prompt: prompt)
            let complexity: Int = (intent == .hardware || intent == .status) ? 0 : 3
            
            let local = self.localProvider
            let runtime = OrchestratorRuntime(
                planner: planner, 
                memory: memory,
                cloudProvider: provider, 
                localProvider: local,
                toolRegistry: toolRegistry,
                bus: bus
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
            
            // 5. Run Task
            let session = Session(workspaceURL: workspaceURL)
            try await runtime.executeTask(prompt: prompt, session: session, complexity: complexity)
            
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
