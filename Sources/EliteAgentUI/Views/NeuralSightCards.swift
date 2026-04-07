import SwiftUI

/// A premium card component for displaying agent insights and metadata.
/// Complies with EliteAgent v10.0 'Titan' design system (8/16pt grid).
public struct NeuralSightCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    public init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundColor(.accentColor)
                
                Text(title.uppercased())
                    .font(.caption2.bold())
                    .tracking(1.5)
                    .foregroundColor(.secondary)
            }
            
            // Content
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) Insight Card")
    }
}

/// A specialized card for token and budget metrics.
public struct MetricCard: View {
    let label: String
    let value: String
    let trend: Double // 0 to 1
    
    public var body: some View {
        NeuralSightCard(title: label, icon: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(.title3, design: .rounded))
                    .bold()
                
                // Progress bar
                ZExternalProgressView(value: trend)
            }
        }
    }
}

fileprivate struct ZExternalProgressView: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.1)).frame(height: 4)
                Capsule().fill(Color.accentColor).frame(width: geo.size.width * value, height: 4)
            }
        }
        .frame(height: 4)
    }
}

#Preview {
    MetricCard(label: "Token Budget", value: "85k / 100k", trend: 0.85)
        .preferredColorScheme(.dark)
        .padding()
}
