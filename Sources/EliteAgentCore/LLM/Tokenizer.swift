import Foundation

import Foundation

public final class BPETokenizer: Sendable {
    public let vocab: [String: Int]
    public let merges: [String: Int]
    private let decoder: [Int: String]
    
    public init(vocab: [String: Int], merges: [String: Int]) {
        self.vocab = vocab
        self.merges = merges
        var dec = [Int: String]()
        for (k, v) in vocab { dec[v] = k }
        self.decoder = dec
    }
    
    public static func load(from directory: URL) throws -> BPETokenizer {
        let vocabURL = directory.appendingPathComponent("tokenizer.json")
        let data = try Data(contentsOf: vocabURL)
        
        struct TokenizerFile: Codable {
            struct Model: Codable {
                let vocab: [String: Int]
                let merges: [String]?
            }
            let model: Model
        }
        
        let decoded = try JSONDecoder().decode(TokenizerFile.self, from: data)
        var mergeMap = [String: Int]()
        if let merges = decoded.model.merges {
            for (index, merge) in merges.enumerated() {
                mergeMap[merge] = index
            }
        }
        
        return BPETokenizer(vocab: decoded.model.vocab, merges: mergeMap)
    }
    
    public func encode(text: String) -> [Int] {
        var tokens = text.map { String($0) }
        
        while true {
            var bestMerge: String? = nil
            var minIndex = Int.max
            
            for i in 0..<tokens.count - 1 {
                let pair = tokens[i] + " " + tokens[i+1]
                if let index = merges[pair], index < minIndex {
                    minIndex = index
                    bestMerge = pair
                }
            }
            
            guard let merge = bestMerge else { break }
            
            let parts = merge.split(separator: " ")
            let first = String(parts[0])
            let second = String(parts[1])
            let replacement = first + second
            
            var newTokens = [String]()
            var i = 0
            while i < tokens.count {
                if i < tokens.count - 1 && tokens[i] == first && tokens[i+1] == second {
                    newTokens.append(replacement)
                    i += 2
                } else {
                    newTokens.append(tokens[i])
                    i += 1
                }
            }
            tokens = newTokens
        }
        
        return tokens.compactMap { vocab[$0] }
    }
    
    public func decode(tokens: [Int]) -> String {
        return tokens.compactMap { decoder[$0] }.joined()
    }
}
