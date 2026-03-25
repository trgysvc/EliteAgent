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
        NSApp.setActivationPolicy(.accessory)
        let vm = ModelPickerViewModel(orchestrator: orchestrator)
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
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.material = .popover
        
        let hostingView = NSHostingView(rootView: 
            MenuBarView(orchestrator: orchestrator)
                .background(.clear)
        )
        hostingView.frame = visualEffect.bounds
        hostingView.autoresizingMask = [.width, .height]
        
        visualEffect.addSubview(hostingView)
        
        let viewController = NSViewController()
        viewController.view = visualEffect
        popover?.contentViewController = viewController
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
