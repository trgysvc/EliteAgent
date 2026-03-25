import AppKit
import SwiftUI
import EliteAgentCore

@MainActor
class ChatWindowController {
    private var window: NSWindow?
    private let orchestrator: Orchestrator
    private let modelPickerVM: ModelPickerViewModel
    
    init(orchestrator: Orchestrator, modelPickerVM: ModelPickerViewModel) {
        self.orchestrator = orchestrator
        self.modelPickerVM = modelPickerVM
    }
    
    func showWindow() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.material = .windowBackground
        
        let hostingView = NSHostingView(rootView: 
            ChatWindowView(orchestrator: orchestrator, modelPickerVM: modelPickerVM)
                .background(Color.clear)
        )
        hostingView.frame = visualEffect.bounds
        hostingView.autoresizingMask = [.width, .height]
        visualEffect.addSubview(hostingView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900.0, height: 600.0),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.title = "Elite Agent"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = visualEffect
        window.isReleasedWhenClosed = false
        
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
