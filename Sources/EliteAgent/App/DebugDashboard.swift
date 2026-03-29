import SwiftUI
import EliteAgentCore

struct DebugDashboard: View {
    @State private var keychainStatus: String = "Checking..."
    @State private var xpcStatus: String = "Checking..."
    @State private var apiKeyState: String = "Checking..."
    @State private var isChecking = false
    @State private var newKey: String = ""
    @State private var showSaveSuccess = false
    
    let orchestrator: Orchestrator
    let keychain = KeychainHelper()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("EliteAgent Diagnostics")
                .font(.headline)
                .padding(.bottom, 8)
            
            Group {
                StatusRow(label: "Keychain Namespace", value: "com.trgysvc.EliteAgent")
                StatusRow(label: "Legacy Fallback", value: "com.eliteagent")
                StatusRow(label: "XPC Service", value: "com.trgysvc.EliteAgent.XPC", color: .blue)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Live Connectivity")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    if isChecking {
                        ProgressView().scaleEffect(0.5)
                    }
                }
                
                ConnectivityRow(label: "XPC Handshake", status: xpcStatus)
                ConnectivityRow(label: "Credential Access", status: apiKeyState)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Manual Key Recovery")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    SecureField("Enter OPENROUTER_API_KEY", text: $newKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    
                    Button("Save") {
                        saveManualKey()
                    }
                    .buttonStyle(.bordered)
                    .disabled(newKey.isEmpty)
                }
                
                if showSaveSuccess {
                    Text("✅ Key saved to Keychain!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            Button(action: runDiagnostics) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Run Health Check")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isChecking)
            
            Text("Tip: If XPC fails with 0x5, ensure the app is signed with the same Team ID as the service.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .frame(width: 320, height: 400)
        .onAppear(perform: runDiagnostics)
    }
    
    private func runDiagnostics() {
        isChecking = true
        
        Task {
            // 1. Check XPC via ShellTool
            do {
                let tool = ShellTool()
                _ = try await tool.execute(params: ["command": AnyCodable("sw_vers -productVersion")], session: .init(workspaceURL: URL(fileURLWithPath: "/")))
                xpcStatus = "✅ Connected (Healthy)"
            } catch {
                xpcStatus = "❌ Failed (\(error.localizedDescription))"
            }
            
            // 2. Check API Key presence
            do {
                let defaultVaultPath = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".eliteagent/vault.plist")
                let manager = try VaultManager(configURL: defaultVaultPath)
                if let provider = await manager.config.providers.first(where: { $0.type == .cloud }) {
                    _ = try await manager.getAPIKey(for: provider)
                    apiKeyState = "✅ Key Found & Accessible"
                } else {
                    apiKeyState = "⚠️ No Cloud Provider defined"
                }
            } catch {
                apiKeyState = "❌ Missing (\(error.localizedDescription))"
            }
            
            isChecking = false
        }
    }
    
    private func saveManualKey() {
        guard !newKey.isEmpty else { return }
        do {
            if let data = newKey.data(using: .utf8) {
                try keychain.save(key: "OPENROUTER_API_KEY", data: data)
                newKey = ""
                showSaveSuccess = true
                runDiagnostics()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showSaveSuccess = false
                }
            }
        } catch {
            apiKeyState = "❌ Save Failed (\(error))"
        }
    }
}

struct StatusRow: View {
    let label: String
    let value: String
    var color: Color = .secondary
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(color)
        }
        .font(.caption)
    }
}

struct ConnectivityRow: View {
    let label: String
    let status: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(status)
                .font(.body)
                .fontWeight(.medium)
        }
    }
}
