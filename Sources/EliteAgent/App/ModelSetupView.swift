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
        VStack(spacing: 24) {
            if manager.isDownloading {
                // DOWNLOAD PROGRESS VIEW
                VStack(spacing: 20) {
                    Text("Downloading Titan Intelligence...")
                        .font(.headline)
                    
                    Text("Fetching \(manager.currentDownloadTask)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ProgressView(value: manager.downloadProgress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .frame(height: 8)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    
                    Text("\(Int(manager.downloadProgress * 100))%")
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)
                }
                .padding(30)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                .shadow(color: .blue.opacity(0.2), radius: 20)
            } else {
                // INITIAL MISSING STATE
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    
                    Text("Local Model Not Detected")
                        .font(.headline)
                    
                    Text("Activate the Titan Engine to enable ultra-fast, 100% private offline reasoning.")
                        .multilineTextAlignment(.center)
                        .font(.body)
                        .padding(.horizontal)
                    
                    Button {
                        manager.startModelDownload()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download Qwen 2.5 (7B-4bit)")
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Text("Est. Size: 4.5 GB • Native MLX Safetensors")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
    
    private var successPhase: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: manager.isModelReady)
            }
            
            Text("Titan Engine Active")
                .font(.system(size: 24, weight: .bold))
            
            Text("Local intelligence is initialized and ready for hardware-accelerated inference.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            HStack {
                Image(systemName: "cpu")
                Text(manager.modelPath?.lastPathComponent ?? "Default Model")
            }
            .font(.system(.caption, design: .monospaced))
            .padding(10)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
        .transition(.asymmetric(insertion: .push(from: .bottom), removal: .opacity))
    }
    
    private var footerView: some View {
        HStack {
            if manager.isModelReady {
                Button { dismiss() } label: {
                    Text("Enter Chat Arena")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.blue)
            } else if !manager.isDownloading {
                Button("Finish Later") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if setupPhase == 0 {
                    Button("Get Started") {
                        withAnimation { setupPhase = 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
    }
    
    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.blue.opacity(0.1)).frame(width: 32, height: 32)
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(desc).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}
