import Foundation

/// v13.8: UNO Master Binary ID Registry (Sealed Census)
/// These IDs map tool calls directly to Binary Signatures for zero-string routing.
public enum ToolUBID: Int, Sendable, CaseIterable {
    // 🎼 Specialized Media Instruments
    case musicDNA = 18
    case mediaControl = 43
    case systemVolume = 56 // Corrected from EcosystemTools.swift
    case systemBrightness = 57 // Corrected from EcosystemTools.swift
    case systemSleep = 15 // Corrected from EcosystemTools.swift
    case systemInfo = 58 // Assigned new for SystemInfo
    
    // 🌐 Web & Research Suite
    case webSearch = 45
    case webFetch = 46
    case safariAutomation = 40
    case nativeBrowser = 170 
    case markdownReport = 20
    
    // 📱 Communication & Social
    case whatsappMessage = 17
    case messengerMessage = 37
    case emailLegacy = 22
    case appleMail = 55 // Corrected from EcosystemTools.swift (was 15)
    case appleCalendar = 54 // Corrected from EcosystemTools.swift
    case contactsLookup = 39
    case calendarEvents = 21 // v11.1 assign
    
    // 💻 System & Workflow
    case appDiscovery = 35
    case shortcutList = 50
    case shortcutRun = 49
    case systemTelemetry = 36
    
    // 📂 Files & Developer Ops
    case fileManager = 38
    case readFile = 33
    case writeFile = 34
    case shellExec = 32
    case patchApply = 41
    case gitOps = 42
    case xcodeBuilder = 47
    
    // 🧠 Advanced AI & Memory
    case memoryContext = 44
    case imageAnalysis = 48
    case subagentDelegate = 19
    
    // 🛠 Basic Utilities (Restored & Sealed)
    case calculatorOp = 80
    case weatherReport = 81
    case systemDate = 82
    case timerSet = 83
    
    // Metadata access
    public var label: String {
        return "\(self)"
    }
}
