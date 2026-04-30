import Foundation
import Cocoa
import ApplicationServices

/// v7.0 Stability: Browser AX Inspector
/// Dumps the accessibility tree of the frontmost Safari page to help the agent discover elements.
public struct BrowserAXInspector {
    public static func dumpFrontmostPage() -> String {
        guard let safari = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first else {
            return "Safari not running."
        }
        
        let app = AXUIElementCreateApplication(safari.processIdentifier)
        var windows: AnyObject?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
        
        guard let windowArray = windows as? [AXUIElement], let frontWindow = windowArray.first else {
            return "No Safari windows found."
        }
        
        var output = "--- Safari AX Tree Dump ---\n"
        dumpElement(frontWindow, depth: 0, output: &output)
        return output
    }
    
    private static func dumpElement(_ element: AXUIElement, depth: Int, output: inout String) {
        if depth > 10 { return } // Depth limit for performance
        
        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        
        var title: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        
        var identifier: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier)
        
        var description: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)
        
        let roleStr = role as? String ?? "UnknownRole"
        let titleStr = title as? String ?? ""
        let idStr = identifier as? String ?? ""
        let descStr = description as? String ?? ""
        
        // Only include interesting elements to keep the dump concise
        let interestingRoles = [kAXButtonRole, kAXTextFieldRole, "AXLink", kAXCheckBoxRole, kAXStaticTextRole, kAXTextAreaRole] as [String]
        
        if interestingRoles.contains(roleStr) || !idStr.isEmpty || !titleStr.isEmpty {
            let indent = String(repeating: "  ", count: depth)
            output += "\(indent)[\(roleStr)] ID: \(idStr) | Title: \(titleStr) | Desc: \(descStr)\n"
        }
        
        var children: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        if let childrenArray = children as? [AXUIElement] {
            for child in childrenArray {
                dumpElement(child, depth: depth + 1, output: &output)
            }
        }
    }
}
