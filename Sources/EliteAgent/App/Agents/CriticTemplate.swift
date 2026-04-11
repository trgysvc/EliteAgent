import Foundation

public struct CriticEvaluation: Codable, Sendable {
    public let score: Int
    public let feedback: String
    public let action: CriticAction
    
    public init(score: Int, feedback: String, action: CriticAction) {
        self.score = score
        self.feedback = feedback
        self.action = action
    }
}

public enum CriticAction: String, Codable, Sendable {
    case reviewPass = "REVIEW_PASS"
    case reviewFail = "REVIEW_FAIL"
    case humanEscalation = "HUMAN_ESCALATION"
}

public struct CriticTemplate: Sendable {
    public static func evaluate(score: Int, feedback: String) -> CriticEvaluation {
        let action: CriticAction
        if score < 7 {
            action = .reviewFail
        } else {
            action = .reviewPass
        }
        return CriticEvaluation(score: score, feedback: feedback, action: action)
    }
}
