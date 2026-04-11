import SwiftUI
import EliteAgentCore

/// Extension for ChatWindowView to integrate the new File Upload and Agent Process visualization.
/// This implementation replaces the legacy file attachment chips and simple workflow views.
extension ChatWindowView {
    
    /// The state-driven overlay for the chat area.
    @ViewBuilder
    func processOverlay(viewModel: ChatProcessViewModel) -> some View {
        switch viewModel.currentState {
        case .idle:
            // The standard drop zone is shown above the input area or as a background overlay
            Color.clear
        case .uploading(let progress):
            ZStack {
                Color.black.opacity(0.1)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                
                UploadProgressView(progress: progress) {
                    viewModel.cancel()
                }
                .transition(.scale.combined(with: .opacity))
                .padding(40)
            }
        case .processing(let step):
            VStack {
                Spacer()
                AgentProcessTimeline(currentStep: step)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        case .success(_):
            // Visual feedback for successful completion can be shown briefly
            HStack {
                Label("İşlem Başarılı", systemImage: "checkmark.circle.fill")
                    .bold()
                    .foregroundStyle(.green)
            }
            .padding()
            .background(.ultraThinMaterial, in: Capsule())
            .transition(.scale)
            .padding()
            .onAppear {
                // Return to idle after success if desired, or let it stick
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation { viewModel.currentState = .idle }
                }
            }
        case .failed(let error):
            VStack {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Hata: \(error)")
                        .font(.caption)
                    Button("Kapat") {
                        viewModel.cancel()
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
            .transition(.move(edge: .bottom))
        }
    }
    
    // Usage Example:
    // Place this inside ChatWindowView's detail view (ZStack)
    /*
     VStack {
         ...
     }
     .overlay {
         processOverlay(viewModel: chatProcessVM)
     }
     .onDrop(...) { ... }
     .onDisappear {
         chatProcessVM.cancel()
     }
    */
}

/// A wrapper view to demonstrate the integration in a clean environment.
struct IntegratedChatView: View {
    @StateObject private var viewModel = ChatProcessViewModel()
    @StateObject private var orchestrator = Orchestrator()
    @StateObject private var modelPickerVM = ModelPickerViewModel()
    
    var body: some View {
        ZStack {
            // Re-using the actual ChatWindowView with modified logic
            ChatWindowView(orchestrator: orchestrator, modelPickerVM: modelPickerVM)
                .overlay {
                    // Injecting the new process visualization
                    ProcessIntegrationView(viewModel: viewModel)
                }
        }
        .onDisappear {
            viewModel.cancel()
        }
    }
}

private struct ProcessIntegrationView: View {
    @ObservedObject var viewModel: ChatProcessViewModel
    
    var body: some View {
        Group {
            switch viewModel.currentState {
            case .uploading(let progress):
                ZStack {
                    Color.black.opacity(0.1)
                        .background(.ultraThinMaterial)
                        .ignoresSafeArea()
                    
                    UploadProgressView(progress: progress) {
                        viewModel.cancel()
                    }
                    .frame(maxWidth: 400)
                }
            case .processing(let step):
                VStack {
                    Spacer()
                    AgentProcessTimeline(currentStep: step)
                        .frame(maxWidth: 500)
                        .padding(.bottom, 100) // Positioned above the message input
                }
            default:
                EmptyView()
            }
        }
    }
}
