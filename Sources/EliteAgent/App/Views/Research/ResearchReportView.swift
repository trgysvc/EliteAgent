import SwiftUI

// MARK: - Data Models (Matches JSON Schema)

public struct ResearchReport: Codable {
    public let report: ReportMeta?
    public let recommendation: Recommendation?
    public let alternatives: [Alternative]?
    public let research: ResearchDetails?
    public let nextSteps: [String]?
    
    enum CodingKeys: String, CodingKey {
        case report, recommendation, alternatives, research, nextSteps
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.report = try container.decodeIfPresent(ReportMeta.self, forKey: .report)
        self.recommendation = try container.decodeIfPresent(Recommendation.self, forKey: .recommendation)
        self.alternatives = try container.decodeIfPresent([Alternative].self, forKey: .alternatives)
        self.research = try container.decodeIfPresent(ResearchDetails.self, forKey: .research)
        self.nextSteps = try container.decodeIfPresent([String].self, forKey: .nextSteps)
    }
}

public struct ReportMeta: Codable {
    public let title: String?
    public let generatedAt: String?
    public let researchDuration: String?
    public let sourcesAnalyzed: Int?
    
    enum CodingKeys: String, CodingKey {
        case title, generatedAt, researchDuration, sourcesAnalyzed
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        self.researchDuration = try container.decodeIfPresent(String.self, forKey: .researchDuration)
        self.sourcesAnalyzed = try container.decodeIfPresent(Int.self, forKey: .sourcesAnalyzed)
    }
}

public struct Recommendation: Codable {
    public let name: String?
    public let confidenceScore: Double?
    public let reasoning: String?
    public let scores: [String: Int]?
    
    enum CodingKeys: String, CodingKey {
        case name, confidenceScore, reasoning, scores
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.confidenceScore = try container.decodeIfPresent(Double.self, forKey: .confidenceScore)
        self.reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning)
        self.scores = try container.decodeIfPresent([String: Int].self, forKey: .scores)
    }
}

public struct Alternative: Codable, Identifiable {
    public var id: String { name ?? UUID().uuidString }
    public let name: String?
    public let pros: [String]?
    public let cons: [String]?
    public let score: Int?
    
    enum CodingKeys: String, CodingKey {
        case name, pros, cons, score
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.pros = try container.decodeIfPresent([String].self, forKey: .pros)
        self.cons = try container.decodeIfPresent([String].self, forKey: .cons)
        self.score = try container.decodeIfPresent(Int.self, forKey: .score)
    }
}

public struct ResearchDetails: Codable {
    public let sources: [ResearchSource]?
    public let competitiveAnalysis: CompetitiveAnalysis?
    
    enum CodingKeys: String, CodingKey {
        case sources, competitiveAnalysis
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sources = try container.decodeIfPresent([ResearchSource].self, forKey: .sources)
        self.competitiveAnalysis = try container.decodeIfPresent(CompetitiveAnalysis.self, forKey: .competitiveAnalysis)
    }
}

public struct ResearchSource: Codable, Identifiable {
    public var id: String { url ?? UUID().uuidString }
    public let title: String?
    public let url: String?
    public let insights: String?
    
    enum CodingKeys: String, CodingKey {
        case title, url, insights
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.insights = try container.decodeIfPresent(String.self, forKey: .insights)
    }
}

public struct CompetitiveAnalysis: Codable {
    public let totalAppsAnalyzed: Int?
    public let averageNameLength: Double?
    public let commonPatterns: [String]?
    public let trademarkRisks: [String]?
    
    enum CodingKeys: String, CodingKey {
        case totalAppsAnalyzed, averageNameLength, commonPatterns, trademarkRisks
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.totalAppsAnalyzed = try container.decodeIfPresent(Int.self, forKey: .totalAppsAnalyzed)
        self.averageNameLength = try container.decodeIfPresent(Double.self, forKey: .averageNameLength)
        self.commonPatterns = try container.decodeIfPresent([String].self, forKey: .commonPatterns)
        self.trademarkRisks = try container.decodeIfPresent([String].self, forKey: .trademarkRisks)
    }
}

// MARK: - ResearchReportView

public struct ResearchReportView: View {
    let report: ResearchReport
    
    @State private var isReasoningExpanded = true
    
    public init(report: ResearchReport) {
        self.report = report
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // 1. Hero Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("🎯 ÖNERİLEN İSİM")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            
                            Text(report.recommendation?.name ?? "İsim Belirlenmedi")
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                                )
                        }
                        
                        Spacer()
                        
                        ConfidenceMeter(score: report.recommendation?.confidenceScore ?? 0.0)
                            .frame(width: 80, height: 80)
                    }
                    
                    Text(report.report?.title ?? "Araştırma Raporu")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                
                // 2. Reasoning Accordion
                if let reasoning = report.recommendation?.reasoning {
                    DisclosureGroup(isExpanded: $isReasoningExpanded) {
                        Text(reasoning)
                            .font(.body)
                            .lineSpacing(4)
                            .padding(.top, 8)
                            .foregroundStyle(.primary.opacity(0.8))
                    } label: {
                        Label("📊 Neden Bu İsim?", systemImage: "chart.bar.doc.horizontal")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                }
                
                // 3. Detailed Scores
                if let scores = report.recommendation?.scores, !scores.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("📈 Detaylı Puanlama")
                            .font(.headline)
                        
                        VStack(spacing: 12) {
                            ForEach(scores.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                ScoreRow(name: key, value: value)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                }
                
                // 4. Alternatives
                VStack(alignment: .leading, spacing: 16) {
                    Text("🔄 Alternatifler")
                        .font(.headline)
                    
                    if let alternatives = report.alternatives, !alternatives.isEmpty {
                        ForEach(alternatives) { alt in
                            AlternativeCard(alternative: alt)
                        }
                    } else {
                        HStack {
                            Text("ℹ️ Alternatifler henüz oluşturulmadı. Araştırma devam ediyor...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.02), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                
                // 5. Sources
                if let sources = report.research?.sources, !sources.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("📚 Araştırma Kaynakları")
                            .font(.headline)
                        
                        ForEach(sources) { source in
                            SourceLinkCard(source: source)
                        }
                    }
                }
                
                // 6. Action Bar
                HStack(spacing: 16) {
                    Button(action: {}) {
                        Label("Bu İsmi Kullan", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button(action: {}) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    
                    Button(action: {}) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
    }
}

// MARK: - Subviews

struct ConfidenceMeter: View {
    let score: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
            
            Circle()
                .trim(from: 0, to: score)
                .stroke(
                    LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            
            VStack(spacing: 0) {
                Text("\(Int(score * 100))%")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
            }
        }
    }
}

struct ScoreRow: View {
    let name: String
    let value: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.subheadline)
                Spacer()
                Text("\(value)/10").font(.caption).monospacedDigit()
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [.blue.opacity(0.7), .blue], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(value) / 10.0)
                }
            }
            .frame(height: 6)
        }
    }
}

struct AlternativeCard: View {
    let alternative: Alternative
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(alternative.name ?? "İsimsiz")
                    .font(.headline)
                Spacer()
                Text("\(alternative.score ?? 0)/50")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.1), in: Capsule())
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(alternative.pros ?? [], id: \.self) { pro in
                        Label(pro, systemImage: "plus.circle.fill").foregroundStyle(.green).font(.caption)
                    }
                    ForEach(alternative.cons ?? [], id: \.self) { con in
                        Label(con, systemImage: "minus.circle.fill").foregroundStyle(.red).font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .onTapGesture { withAnimation { isExpanded.toggle() } }
    }
}

struct SourceLinkCard: View {
    let source: ResearchSource
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(source.title ?? "Başlıksız Kaynak")
                .font(.subheadline)
                .fontWeight(.bold)
            
            Text(source.insights ?? "Özet bilgi yok.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if let urlString = source.url, let url = URL(string: urlString) {
                Link(destination: url) {
                    Text(urlString)
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
    }
}
