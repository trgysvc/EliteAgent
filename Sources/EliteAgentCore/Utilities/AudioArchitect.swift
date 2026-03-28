import Foundation

public actor AudioArchitect {
    public static let shared = AudioArchitect()
    
    private var previousVolume: Int?
    
    private init() {}
    
    public func dampen() async {
        do {
            // Get current volume
            let currentVolStr = try await AppleScriptRunner.shared.execute(source: "output volume of (get volume settings)")
            self.previousVolume = Int(currentVolStr.trimmingCharacters(in: .whitespacesAndNewlines))
            
            // Fade out to 10%
            for i in stride(from: (previousVolume ?? 50), through: 10, by: -5) {
                _ = try await AppleScriptRunner.shared.execute(source: "set volume output volume \(i)")
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms per step
            }
        } catch {
            print("[AUDIO] Dampen failed: \(error)")
        }
    }
    
    public func restore() async {
        guard let target = previousVolume else { return }
        do {
            // Fade in back to previous volume
            for i in stride(from: 10, through: target, by: 5) {
                _ = try await AppleScriptRunner.shared.execute(source: "set volume output volume \(i)")
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms per step
            }
        } catch {
            print("[AUDIO] Restore failed: \(error)")
        }
    }
}
