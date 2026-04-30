import Foundation

/// v13.8: UNO Native Tokenizer Protocol
public protocol UNOTokenizer: Sendable {
    func encode(text: String) -> [Int]
    func decode(tokens: [Int]) -> String
    var unknownTokenID: Int? { get }
}

public final class BPETokenizer: UNOTokenizer, @unchecked Sendable {
    public let vocab: [String: Int]
    public let merges: [String: Int]
    private let decoder: [Int: String]
    public let unknownTokenID: Int?
    
    public init(vocab: [String: Int], merges: [String: Int], unknownTokenID: Int? = nil) {
        self.vocab = vocab
        self.merges = merges
        self.unknownTokenID = unknownTokenID
        var dec = [Int: String]()
        for (k, v) in vocab { dec[v] = k }
        self.decoder = dec
    }
    
    public static func load(from directory: URL) throws -> BPETokenizer {
        let vocabURL = directory.appendingPathComponent("tokenizer.json")
        let data = try Data(contentsOf: vocabURL)
        
        // v13.8: UNO Pure - Delegate resource decoding to External Bridge
        let manifest = UNOExternalBridge.loadTokenizerManifest(data: data)
        
        return BPETokenizer(vocab: manifest.vocab, merges: manifest.merges, unknownTokenID: manifest.vocab["<|endoftext|>"])
    }
    
    public func encode(text: String) -> [Int] {
        // v13.9: Corrected BPE encoding loop for Qwen-style vocab
        var tokens = text.map { String($0) }
        
        while true {
            var bestPair: (Int, Int)? = nil
            var minMergeIndex = Int.max
            
            for i in 0..<tokens.count - 1 {
                let pair = tokens[i] + " " + tokens[i+1]
                if let index = merges[pair], index < minMergeIndex {
                    minMergeIndex = index
                    bestPair = (i, i+1)
                }
            }
            
            guard let pairIndices = bestPair else { break }
            
            let first = tokens[pairIndices.0]
            let second = tokens[pairIndices.1]
            let replacement = first + second
            
            var newTokens = [String]()
            var i = 0
            while i < tokens.count {
                if i == pairIndices.0 {
                    newTokens.append(replacement)
                    i += 2
                } else {
                    newTokens.append(tokens[i])
                    i += 1
                }
            }
            tokens = newTokens
        }
        
        return tokens.compactMap { vocab[$0] ?? unknownTokenID }
    }
    
    public func decode(tokens: [Int]) -> String {
        return tokens.compactMap { decoder[$0] }.joined()
    }
}
