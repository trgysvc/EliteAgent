import Foundation
import Combine
import CryptoKit

public enum SecurityError: Error, Sendable {
    case invalidSignature(sigID: UUID)
}


public actor SignalBus {
    private weak var orchestrator: Orchestrator?
    public let sharedSecret: SymmetricKey
    
    public init(sharedSecret: SymmetricKey = SymmetricKey(size: .bits256)) {
        self.sharedSecret = sharedSecret
    }
    
    public func setOrchestrator(_ orchestrator: Orchestrator) {
        self.orchestrator = orchestrator
    }
    
    public func dispatch(_ signal: Signal) async throws {
        guard signal.verifySignature(using: sharedSecret) else {
            throw SecurityError.invalidSignature(sigID: signal.sigID)
        }
        guard let orchestrator else { return }
        try await orchestrator.receive(signal)
    }
}

@MainActor
public final class Orchestrator: ObservableObject {
    public let agentID: AgentID = .orchestrator
    @Published public private(set) var status: AgentStatus = .idle
    @Published public var currentTask: String = ""
    @Published public var steps: [TaskStep] = []
    @Published public var thinkBlocks: [ThinkBlock] = []
    @Published public var providerUsed: String = "None"
    @Published public var costToday: Decimal = 0.00
    
    private let bus: SignalBus
    private let planner: PlannerAgent
    private let memory: MemoryAgent
    private var cloudProvider: CloudProvider?
    private let toolRegistry: ToolRegistry
    private var observer: ProjectObserver?
    
    public init() {
        let bus = SignalBus()
        self.bus = bus
        self.planner = PlannerAgent(bus: bus)
        self.memory = MemoryAgent(bus: bus)
        
        // Initialize Core Services
        let defaultVaultPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".eliteagent/vault.plist")
        do {
            let vault = try VaultManager(configURL: defaultVaultPath)
            self.cloudProvider = try CloudProvider(providerID: ProviderID(rawValue: "openrouter"), vaultManager: vault)
        } catch {
            print("[ORCHESTRATOR] CRITICAL: Failed to initialize Core Services: \(error)")
            self.status = .error
            self.cloudProvider = nil
        }
        
        // Initialize Tool Registry
        self.toolRegistry = ToolRegistry()
        self.toolRegistry.register(ShellTool())
        self.toolRegistry.register(ReadFileTool())
        self.toolRegistry.register(WriteFileTool())
        self.toolRegistry.register(NativeBrowserTool())
        self.toolRegistry.register(CalendarTool())
        self.toolRegistry.register(MailTool())
        self.toolRegistry.register(MediaControllerTool())
        
        // Register SubagentTool (Recursive)
        let handler: @Sendable (TaskStep) -> Void = { [weak self] step in
            Task { @MainActor [weak self] in
                self?.steps.append(step)
            }
        }
        
        if let provider = self.cloudProvider {
            let subagentTool = SubagentTool(planner: self.planner, cloudProvider: provider, onStepUpdate: handler) { [weak self] planner, provider in
                guard let self = self else { fatalError() }
                return OrchestratorRuntime(planner: planner, memory: self.memory, cloudProvider: provider, toolRegistry: ToolRegistry.shared)
            }
            self.toolRegistry.register(subagentTool)
        }
        
        // Initialize Auto-Update (Sparkle)
        #if !DEBUG
        UpdaterService.shared.checkForUpdates()
        #endif
    }
    
    public func start() async {
        await bus.setOrchestrator(self)
    }
    
    public func receive(_ signal: Signal) async throws {
        if signal.name == "CLARIFY_REQUEST" {
            guard let question = String(data: signal.payload, encoding: .utf8) else { return }
            self.steps.append(TaskStep(name: "Clarification: \(question)", status: "working", latency: "0ms"))
        }
    }

    public func submitTask(prompt: String) async throws {
        self.status = .working
        self.steps.removeAll()
        self.thinkBlocks.removeAll()
        self.currentTask = prompt
        
        let taskStart = CFAbsoluteTimeGetCurrent()
        
        do {
            // 1. Create Workspace
            let sessionID = UUID()
            let workspaceURL = try WorkspaceManager.shared.createWorkspace(for: sessionID)
            
            // 2. Create Root Session
            let session = Session(id: sessionID, workspaceURL: workspaceURL)
            
            // 3. Create Runtime
            guard let provider = self.cloudProvider else {
                throw ProviderError.networkError("Cloud Provider not initialized. Please check your vault.plist and API keys.")
            }
            
            let runtime = OrchestratorRuntime(
                planner: planner, 
                memory: memory,
                cloudProvider: provider, 
                toolRegistry: toolRegistry
            )
            
            // 3b. Start Project Observer
            self.observer?.stop()
            self.observer = ProjectObserver(path: workspaceURL.path, delegate: self)
            self.observer?.start()
            
            // 4. Set UI Callbacks
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
            
            self.steps.append(TaskStep(name: "Initializing recursive runtime...", status: "done", latency: "0ms"))
            
            // 5. Run Task
            try await runtime.executeTask(prompt: prompt, session: session)
            
            let finalAnswer = await session.finalAnswer ?? "Task completed."
            let elapsed = CFAbsoluteTimeGetCurrent() - taskStart
            
            self.steps.append(TaskStep(name: finalAnswer, status: "done", latency: "\(Int(elapsed))s"))
            self.status = .idle
            
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - taskStart
            self.status = .error
            self.steps.append(TaskStep(name: "Error: \(error.localizedDescription)", status: "failed", latency: "\(Int(elapsed))s"))
        }
    }
}

extension Orchestrator: ProjectObserverDelegate {
    public func projectDidDetectChange(at path: String, flags: FSEventStreamEventFlags) {
        // Only trigger for interesting files (.swift, .md, .plist)
        let interestingExts = ["swift", "md", "plist", "json"]
        guard interestingExts.contains(where: { path.hasSuffix($0) }) else { return }
        
        // Use Task since Orchestrator is @MainActor and we need to append to steps
        Task { @MainActor in
            let step = TaskStep(
                name: "Proactive: Detected change in \(URL(fileURLWithPath: path).lastPathComponent)", 
                status: "done", 
                latency: "0ms",
                depth: 0,
                thought: "Should I verify this change or generate a Unit Test?"
            )
            self.steps.append(step)
            AgentLogger.logAudit(level: .info, agent: "Orchestrator", message: "Proactive observer triggered for \(path)")
        }
    }
}
