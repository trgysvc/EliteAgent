import SwiftUI
import EliteAgentCore

public struct ModelSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ModelSetupViewModel
    
    public init(vault: VaultManager) {
        self.viewModel = ModelSetupViewModel(vault: vault)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add New LLM Connection")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.thinMaterial)
            
            Form {
                Section("Connection Details") {
                    TextField("Connection Name", text: $viewModel.displayName)
                        .textFieldStyle(.roundedBorder)
                    
                    Picker("Provider Type", selection: $viewModel.providerType) {
                        Text("OpenRouter").tag(ProviderType.cloud)
                        Text("Ollama / Local").tag(ProviderType.local)
                    }
                    
                    TextField("Base URL", text: $viewModel.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    
                    SecureField("API Key (Optional)", text: $viewModel.apiKey)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Model ID", text: $viewModel.modelID)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .help("e.g. google/gemini-3.1-flash-lite-preview or llama3")
                }
                
                Section("Parameters") {
                    HStack {
                        Text("Temperature: \(viewModel.temperature, specifier: "%.1f")")
                        Slider(value: $viewModel.temperature, in: 0...2, step: 0.1)
                    }
                    
                    HStack {
                        Text("Top-P: \(viewModel.topP, specifier: "%.2f")")
                        Slider(value: $viewModel.topP, in: 0...1, step: 0.05)
                    }
                    
                    HStack {
                        Text("Max Tokens")
                        Spacer()
                        TextField("", value: $viewModel.maxTokens, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
                
                Section("Capabilities") {
                    Toggle("Supports Vision", isOn: $viewModel.supportsVision)
                    Toggle("Supports Reasoning (Think Blocks)", isOn: $viewModel.supportsReasoning)
                }
            }
            .formStyle(.grouped)
            
            // Footer with Test and Save
            VStack(spacing: 12) {
                if let error = viewModel.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                HStack(spacing: 16) {
                    Button(action: { 
                        Task { await viewModel.testConnection() } 
                    }) {
                        HStack {
                            if viewModel.isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Connect & Verify")
                            Circle()
                                .fill(statusColor)
                                .frame(width: 10, height: 10)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isTesting)
                    
                    Button("Save Configuration") {
                        Task {
                            if await viewModel.save() {
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isVerified || viewModel.isTesting)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .frame(width: 450, height: 600)
    }
    
    private var statusColor: Color {
        if viewModel.isTesting { return .yellow }
        if viewModel.isVerified { return .green }
        if viewModel.lastError != nil { return .red }
        return .gray
    }
}

@MainActor
class ModelSetupViewModel: ObservableObject {
    @Published var displayName: String = "My New Model"
    @Published var providerType: ProviderType = .cloud
    @Published var baseURL: String = "https://openrouter.ai/api/v1"
    @Published var apiKey: String = ""
    @Published var modelID: String = "google/gemini-3.1-flash-lite-preview"
    
    @Published var temperature: Double = 0.7
    @Published var topP: Double = 1.0
    @Published var maxTokens: Int = 4096
    
    @Published var supportsVision: Bool = true
    @Published var supportsReasoning: Bool = false
    
    @Published var isTesting: Bool = false
    @Published var isVerified: Bool = false
    @Published var lastError: String?
    
    private let vault: VaultManager
    private let tester = LLMConnectionTestService()
    
    init(vault: VaultManager) {
        self.vault = vault
    }
    
    func testConnection() async {
        isTesting = true
        lastError = nil
        isVerified = false
        
        guard let url = URL(string: baseURL) else {
            lastError = "Invalid Base URL"
            isTesting = false
            return
        }
        
        let result = await tester.testConnection(baseURL: url, apiKey: apiKey, modelID: modelID)
        
        switch result {
        case .success(let name):
            isVerified = true
            print("[Test] Connection successful for model: \(name)")
        case .failure(let error):
            lastError = error
        }
        
        isTesting = false
    }
    
    func save() async -> Bool {
        guard isVerified else { return false }
        
        let providerID = "custom-\(UUID().uuidString.prefix(6))"
        let keychainKey = apiKey.isEmpty ? nil : "\(providerID)_API_KEY"
        
        if let keychainKey = keychainKey {
            // Store API Key in Keychain
            let keychain = KeychainHelper()
            try? keychain.save(key: keychainKey, data: apiKey.data(using: .utf8)!)
        }
        
        var caps: [String] = []
        if supportsVision { caps.append("vision") }
        if supportsReasoning { caps.append("reasoning") }
        caps.append("tools") // Most models support tools nowadays
        
        let newProvider = ProviderConfig(
            id: providerID,
            type: providerType,
            endpoint: baseURL,
            keychainKey: keychainKey,
            modelName: modelID,
            capabilities: caps,
            costPer1KTokens: nil as Decimal?,
            promptPrice: nil as Decimal?,
            completionPrice: nil as Decimal?,
            maxContextTokens: 128000,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens
        )
        
        do {
            try await vault.addProvider(newProvider)
            return true
        } catch {
            lastError = "Failed to save to vault: \(error.localizedDescription)"
            return false
        }
    }
}
