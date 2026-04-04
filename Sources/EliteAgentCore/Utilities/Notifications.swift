import Foundation

public extension Notification.Name {
    /// Triggers the Model Setup wizard in the main application.
    static let openModelSetup = Notification.Name("OpenModelSetup")
    
    /// Triggers the Settings sheet in the main application.
    static let openSettings = Notification.Name("OpenSettings")
    
    /// Brings the main Chat window to the front.
    static let openChat = Notification.Name("OpenChatWindow")
}
