import SwiftUI
import EliteAgentCore

/// EliteAgent v9.9.5: Resilient Self-Healing UI.
/// Appears when a local model is corrupted/missing on startup.
public struct SelfHealingOverlay: View {
    @ObservedObject var stateManager = ModelStateManager.shared
    @State private var isRepairing = false
    
    public var body: some View {
        if let modelID = stateManager.pendingRepairModelID {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    HStack(spacing: 16) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Yerel Model Onarımı Gerekli")
                                .font(.headline)
                            Text("\(modelID) dosyaları eksik veya bozuk tespit edildi. Sistem sürekliliği için otomatik onarım başlatılmalı.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    VStack(spacing: 12) {
                        Button {
                            repair(useCloud: true)
                        } label: {
                            HStack {
                                Label("Onar ve Bulut ile Devam Et", systemImage: "sparkles.tv")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            repair(useCloud: false)
                        } label: {
                            Text("Sadece Onar (Çevrimdışı Bekle)")
                                .font(.subheadline.bold())
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
                .frame(width: 420)
                .shadow(radius: 20)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    private func repair(useCloud: Bool) {
        withAnimation { isRepairing = true }
        Task {
            await stateManager.confirmRepairAndContinue(useCloudInMeantime: useCloud)
        }
    }
}
