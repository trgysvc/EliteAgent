import SwiftUI
import AppKit
import EliteAgentCore

@main
struct EliteAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    let orchestrator = Orchestrator()
    var chatController: ChatWindowController?
    var modelPickerVM: ModelPickerViewModel?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AgentLogger.logAudit(level: .info, agent: "system", message: "🚀 EliteAgent v10.5.5 Starting Up...")
        NSApp.setActivationPolicy(.accessory)
        
        // v9.9.1: Register Defaults
        UserDefaults.standard.register(defaults: [
            "enableResearchMode": false,
            "debugParser": false,
            "stallThreshold": 3
        ])
        
        // STARTUP BIOMETRIC AUTH
        if AppSettings.shared.isBiometricEnabledForStartup {
            AgentLogger.logAudit(level: .info, agent: "system", message: "🔐 Biometric Auth Triggered")
            Task { @MainActor in
                let success = await SecuritySentinel.shared.authenticateUser(reason: "EliteAgent Erişimi İçin Onay Gerekiyor")
                if !success {
                    AgentLogger.logAudit(level: .security, agent: "system", message: "❌ Biometric Auth Failed. Terminating.")
                    NSApp.terminate(nil)
                    return
                }
                AgentLogger.logAudit(level: .info, agent: "system", message: "✅ Biometric Auth Success")
                finishLaunching()
            }
        } else {
            finishLaunching()
        }
    }
    
    private func finishLaunching() {
        let vm = ModelPickerViewModel()
        self.modelPickerVM = vm
        
        chatController = ChatWindowController(orchestrator: orchestrator, modelPickerVM: vm)
        setupNotification()
        setupMenuBar()
        
        Task {
            await vm.loadModels()
        }
    }
    
    private func setupNotification() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenChatWindow"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.chatController?.showWindow()
            }
        }
    }
    
    func setupMenuBar() {
        print("[EliteAgent] setupMenuBar called")
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "sparkles",
                accessibilityDescription: "Elite Agent"
            )
            button.action = #selector(togglePopover)
            button.target = self
        }
        popover = NSPopover()
        
        let menuBarView = MenuBarView(orchestrator: orchestrator, modelPickerVM: modelPickerVM!)
            .background(Color.clear)
        
        // v20.5: Definitively kill layout recursion by disabling ALL sizingOptions.
        // This stops the hosting controller from trying to reach back into SwiftUI 
        // for sizing during a layout pass, which was causing the 0x5/recursion hang.
        let hostingController = NSHostingController(rootView: menuBarView)
        hostingController.sizingOptions = [] // No auto-sizing
        hostingController.view.frame.size = NSSize(width: 320, height: 520)
        popover?.contentViewController = hostingController
        popover?.behavior = .transient
    }
    
    @objc func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds,
                         of: button, preferredEdge: .minY)
        }
    }
}
