import SwiftUI
import EliteAgentCore

struct ToolRow: View {
    let name: String
    let status: ToolStatus
    @Binding var isEnabled: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                    Text("Calls: \(status.callCount) | Crashes: \(status.crashCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    
                    Text(statusText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.1))
                .cornerRadius(4)
                
                Toggle("", isOn: $isEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    .labelsHidden()
            }
            
            if let error = status.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.05))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var statusColor: Color {
        if !isEnabled { return .gray }
        if status.isAvailable && status.crashCount == 0 { return .green }
        if !status.isAvailable { return .red }
        return .yellow
    }
    
    private var statusText: String {
        if !isEnabled { return "Disabled" }
        if status.isAvailable && status.crashCount == 0 { return "Active" }
        if !status.isAvailable { return "Failed" }
        return "Warning"
    }
}

struct ToolsSettingsView: View {
    @State private var config: InferenceConfig = .default
    @State private var toolStatuses: [String: ToolStatus] = [:]
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Ajan Araçları")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("EliteAgent'ın sahip olduğu yetenekleri buradan yönetebilirsiniz. 3 kez üst üste çöken araçlar güvenlik için otomatik olarak devre dışı bırakılır.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Araştırma Modu (Research Mode)")
                        .font(.headline)
                    
                    VStack(spacing: 12) {
                        Toggle("Safari Otomasyonu", isOn: $config.isSafariAutomationEnabled)
                        Text("Ajanın Safari tarayıcısını kullanarak derinlemesine içerik taramasına izin verir.")
                            .font(.caption).foregroundColor(.secondary)
                        
                        Divider()
                        
                        Toggle("Derin Araştırma (Deep Research)", isOn: $config.isDeepResearchEnabled)
                        Text("Daha fazla kaynak tarar ve akademik düzeyde rapor hazırlar (Daha fazla token tüketir).")
                            .font(.caption).foregroundColor(.secondary)
                        
                        Divider()
                        
                        Toggle("Araştırma İlerlemesini Göster", isOn: $config.showResearchProgress)
                        
                        Divider()
                        
                        Toggle("Raporları Otomatik Kaydet", isOn: $config.autoSaveReports)
                        
                        Divider()
                        
                        HStack {
                            Text("Tercih Edilen Arama Motoru")
                                .font(.subheadline)
                            Spacer()
                            Picker("", selection: $config.preferredSearchProvider) {
                                Text("Serper (Google)").tag("Serper (Google)")
                                Text("Brave Search").tag("Brave Search")
                            }
                            .pickerStyle(.menu)
                            .frame(width: 150)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .onChange(of: config.isSafariAutomationEnabled) { saveConfig() }
                    .onChange(of: config.isDeepResearchEnabled) { saveConfig() }
                    .onChange(of: config.showResearchProgress) { saveConfig() }
                    .onChange(of: config.autoSaveReports) { saveConfig() }
                    .onChange(of: config.preferredSearchProvider) { saveConfig() }
                }
                
                Divider()
                
                VStack(spacing: 0) {
                    ForEach(sortedToolNames, id: \.self) { name in
                        ToolRow(
                            name: name,
                            status: toolStatuses[name] ?? ToolStatus(),
                            isEnabled: Binding(
                                get: { config.enabledTools[name] ?? true },
                                set: { newValue in
                                    config.enabledTools[name] = newValue
                                    saveConfig()
                                }
                            )
                        )
                        
                        if name != sortedToolNames.last {
                            Divider()
                                .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
            }
            .padding()
        }
        .onAppear { refresh() }
        .onReceive(timer) { _ in refresh() }
    }
    
    private var sortedToolNames: [String] {
        toolStatuses.keys.sorted()
    }
    
    private func refresh() {
        Task {
            let currentConfig = await ConfigManager.shared.get()
            let registry = ToolRegistry.shared
            let allTools = await registry.listTools()
            var newStatuses: [String: ToolStatus] = [:]
            
            for tool in allTools {
                newStatuses[tool.name] = await registry.getToolStatus(named: tool.name)
            }
            
            await MainActor.run {
                self.config = currentConfig
                self.toolStatuses = newStatuses
            }
        }
    }
    
    private func saveConfig() {
        let configToSave = self.config
        Task {
            await ConfigManager.shared.save(configToSave)
        }
    }
}
