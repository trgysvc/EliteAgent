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
        
        self.planner = PlannerAgent(bus: bus)
        self.memory = MemoryAgent(bus: bus)
        self.toolRegistry = ToolRegistry.shared
        
        // Titan: Proactive hardware telemetry
        _ = SystemWatchdog.shared
        
        let defaultVaultPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".eliteagent/vault.plist")
        
        do {
            let vault = try VaultManager(configURL: defaultVaultPath)
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
            let configURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".eliteagent/vault.plist")
            let v = try! VaultManager(configURL: configURL)
            safeProvider = try! CloudProvider(providerID: ProviderID(rawValue: "openrouter"), vaultManager: v)
        }
        
        let local = self.localProvider
        let subagentTool = SubagentTool(planner: self.planner, cloudProvider: safeProvider, onStepUpdate: handler) { [weak self] planner, provider in
            guard let self = self else { fatalError() }
            return OrchestratorRuntime(planner: planner, memory: self.memory, cloudProvider: provider, localProvider: local, toolRegistry: ToolRegistry.shared, bus: self.bus)
        }
        self.toolRegistry.register(subagentTool)
    }

    
    public func submitTask(prompt: String) async throws {
        let taskStart = CFAbsoluteTimeGetCurrent()
        self.status = .working
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
            
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - taskStart
            self.status = .error
            self.steps.append(TaskStep(name: "Error: \(error.localizedDescription)", status: "failed", latency: "\(Int(elapsed))s"))
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
