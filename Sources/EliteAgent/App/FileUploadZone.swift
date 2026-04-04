import SwiftUI
import UniformTypeIdentifiers
import EliteAgentCore

/// A refined drop zone for file uploads with HIG-compliant animations and materials.
public struct FileUploadZone: View {
    @State private var isDraggingOver = false
    @State private var showingFileImporter = false
    let onFileAccepted: (URL) -> Void
    
    public init(onFileAccepted: @escaping (URL) -> Void) {
        self.onFileAccepted = onFileAccepted
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 30)
                    .fill(isDraggingOver ? Color.accentColor.opacity(0.1) : Color.clear)
                    .background(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 30)
                            .strokeBorder(
                                isDraggingOver ? Color.accentColor : Color.primary.opacity(0.1),
                                style: StrokeStyle(lineWidth: 2, dash: isDraggingOver ? [10, 5] : [])
                            )
                    )
                    .animation(.easeInOut(duration: 0.2), value: isDraggingOver)
                
                VStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.largeTitle.weight(.light))
                        .foregroundStyle(isDraggingOver ? Color.accentColor : .secondary)
                        .symbolEffect(.pulse, options: .repeating, isActive: isDraggingOver)
                    
                    VStack(spacing: 8) {
                        Text("Döküman Analizi")
                            .font(.title3.bold())
                        
                        Text("PDF, TXT, MD veya Swift dosyası sürükleyin")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Button("Dosya Seç") {
                        showingFileImporter = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.accentColor)
                }
                .padding(40)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1.6, contentMode: .fit)
            .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url {
                        Task { @MainActor in
                            onFileAccepted(url)
                        }
                    }
                }
                return true
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .plainText, .swiftSource, .json, .text],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                onFileAccepted(url)
            }
        }
    }
}

/// A smooth progress bar for file uploads with color shifts and HIG-compliant materials.
public struct UploadProgressView: View {
    let progress: Double
    let onCancel: () -> Void
    
    public var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Dosya Yükleniyor...", systemImage: "arrow.up.doc.fill")
                    .font(.headline)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.body.monospacedDigit())
                    .bold()
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 8)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, progress > 0.9 ? .green : Color.accentColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(progress), height: 12)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
                }
            }
            .frame(height: 12)
            
            Button(role: .destructive) {
                onCancel()
            } label: {
                Label("İptal Et", systemImage: "xmark.circle")
            }
            .buttonStyle(.plain)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }
}

#Preview {
    VStack {
        FileUploadZone { _ in }
        UploadProgressView(progress: 0.65) { }
    }
    .padding()
}
