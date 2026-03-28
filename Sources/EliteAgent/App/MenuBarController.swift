import AppKit
import SwiftUI
import EliteAgentCore

@MainActor
public class MenuBarController {
    public static let shared = MenuBarController()
    
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    
    private init() {}
    
    public func setup(orchestrator: Orchestrator) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "brain.filled.head.profile", accessibilityDescription: "Elite Agent")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        let menuBarView = MenuBarView(orchestrator: orchestrator)
        let hostingController = NSHostingController(rootView: menuBarView)
        
        popover = NSPopover()
        popover.appearance = nil
        popover.contentSize = NSSize(width: 300, height: 160)
        popover.behavior = .transient
        popover.contentViewController = hostingController
    }
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
        }
    }
}
