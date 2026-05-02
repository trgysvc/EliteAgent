import Foundation

/// v30.0: UNO Master Service Protocol (Binary-Native)
/// This defines the contract between the Elite CLI and the background EliteService.
@objc(EliteServiceProtocol)
public protocol EliteServiceProtocol: NSObjectProtocol {
    /// Submits a task to the background orchestrator.
    func submitTask(prompt: String, withReply completion: @escaping @Sendable (String?, Error?) -> Void)
    
    /// Checks the current status and health of the background engine.
    func getStatus(withReply completion: @escaping @Sendable (String?, Error?) -> Void)
    
    /// Forcefully re-primes the model in VRAM.
    func reprimeEngine(withReply completion: @escaping @Sendable (Bool, Error?) -> Void)
}
