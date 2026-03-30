import SwiftUI
import EliteAgentCore

/// Premium Setup Assistant for the Titan Engine (Local MLX Intelligence).
public struct ModelSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = ModelSetupManager.shared
    @State private var setupPhase: Int = 0 
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            // Subtle Radial Gradient for "Titan" feel
            RadialGradient(
                colors: [Color.blue.opacity(0.15), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                headerView
                
                // Content Switcher
                if manager.isModelReady {
                    successPhase
                } else if setupPhase == 0 {
                    welcomePhase
                } else {
                    instructionsPhase
                }
                
                Spacer()
                
                // Footer
                footerView
            }
            .padding(40)
        }
        .frame(width: 500, height: 600)
    }
    
    // MARK: - Components
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 40))
                .foregroundStyle(.linearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                .symbolEffect(.pulse)
            
            Text("Elite Titan Engine")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            
            Text("Hybrid Intelligence Activation")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var welcomePhase: some View {
        VStack(spacing: 20) {
            Text("Powering your workspace with local Apple Silicon intelligence.")
                .multilineTextAlignment(.center)
                .font(.body)
            
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "lock.shield.fill", title: "100% Private", desc: "No data ever leaves your device.")
                featureRow(icon: "bolt.fill", title: "Metal Optimized", desc: "Native M-series GPU acceleration.")
                featureRow(icon: "wifi.slash", title: "Offline Ready", desc: "Works without an internet connection.")
            }
            .padding()
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        }
    }
    
    private var instructionsPhase: some View {
        VStack(spacing: 20) {
            Text("Local Model Not Detected")
                .font(.headline)
                .foregroundStyle(.orange)
            
            Text("To activate the Titan Engine, please place a compatible MLX model in your local models directory.")
                .multilineTextAlignment(.center)
                .font(.body)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Command Line Setup:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("huggingface-cli download mlx-community/Mistral-7B-Instruct-v0.3-4bit --local-dir \(manager.modelsDirectory.path)")
                    .font(.system(.caption, design: .monospaced))
                    .padding(12)
                    .background(.black, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1)))
            }
            .padding()
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            
            Button("Check Directory Again") {
                manager.checkModelStatus()
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var successPhase: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            Text("Titan Engine Active")
                .font(.headline)
            
            Text("Local model detected and optimized for your M-series chip.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            Text(manager.modelPath?.lastPathComponent ?? "Default Model")
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .transition(.scale.combined(with: .opacity))
    }
    
    private var footerView: some View {
        HStack {
            if !manager.isModelReady {
                Button("Configure External Cloud...") {
                    // Logic to jump to cloud setup if preferred
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.blue)
                
                Spacer()
                
                Button(setupPhase == 0 ? "Next" : "Finish Later") {
                    if setupPhase == 0 {
                        withAnimation { setupPhase = 1 }
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button("Begin Experience") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.blue)
            }
        }
    }
    
    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(desc).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}
